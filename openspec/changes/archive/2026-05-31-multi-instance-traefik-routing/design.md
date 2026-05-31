## Context

The backend stack is currently a single `docker compose` project (`project=backend`) with Traefik as the sole HTTP entry point on port 80. Routing is done entirely via a file provider (`traefik/dynamic/app.yml`), which the blue-green `deploy.sh` rewrites at deploy time. Three CI test suites (e2e, migration, lint) hard-code assumptions about this layout:

- e2e scripts call `docker compose ps/down/up` with no project flag → implicitly target project `backend`
- migration script starts services with `docker compose up -d traefik ...` → Traefik must live in the default compose project
- `deploy.sh` writes `traefik/dynamic/app.yml` and uses Docker network `backend_default` and container DNS `app:3000`

Any multi-instance approach must not break these contracts for INSTANCE=1.

## Goals / Non-Goals

**Goals:**
- `make dev-start <N>` launches a fully isolated backend stack (app + MongoDB + PostgreSQL + Redis + Collector + Alloy) for instance N
- Each instance is reachable at `http://instance-N.localhost` via Traefik Docker provider label routing
- Each instance has its own Alloy container with instance-specific configuration (`ALLOY_DOMAIN-N` and tenant ID `<ALLOY_DOMAIN>-<ALLOY_STAGE>-N`)
- INSTANCE=1 is 100% backward-compatible: project name, network name (`backend_default`), volume paths, and `http://localhost` file-provider routing all remain unchanged
- All three CI test suites continue to pass without modification
- Volumes are namespaced per instance to prevent data collision
- A single shared Traefik container (belonging to INSTANCE=1's compose project) routes all instances

**Non-Goals:**
- TLS / HTTPS termination for instance subdomains
- Kubernetes or remote-cluster deployment (local dev only)
- Production-grade multi-tenancy isolation

## Decisions

### Decision 1: Keep Traefik inside `docker-compose.yaml` (not a separate compose file)

**Chosen:** Traefik stays in the main `docker-compose.yaml`, owned by the INSTANCE=1 project.

**Rationale:** `scripts/migration/01-start-blue.sh` runs `docker compose up -d --wait traefik ...` against the default project. Extracting Traefik to `docker-compose.traefik.yml` would require modifying migration scripts, risking CI breakage. Keeping it in the default project preserves the migration test contract with zero script changes (beyond adding the `traefik_net` guard).

**Alternative rejected:** Separate `docker-compose.traefik.yml` with `docker compose -f traefik.yml -f docker-compose.yaml`. Rejected because it requires touching migration and e2e scripts that have implicit project-name assumptions.

---

### Decision 2: Dual provider strategy (file + Docker), not Docker-only

**Chosen:** `traefik.yml` enables both `providers.file` (existing) and `providers.docker` (new, scoped to `traefik_net`).

**Rationale:** `deploy.sh` switches upstreams by overwriting `traefik/dynamic/app.yml`. This file-provider mechanism must remain intact for blue-green deploys. The Docker provider is additive: it only discovers containers with `traefik.enable=true` on `traefik_net`, so it does not conflict with the existing catch-all `PathPrefix("/")` file route.

**Alternative rejected:** Pure Docker provider with labels replacing `app.yml`. Rejected because `deploy.sh` is a production deploy tool not under this change's scope.

---

### Decision 3: INSTANCE=1 uses default compose project; INSTANCE≥2 uses `-p backend-N`

**Chosen:** Makefile sets `COMPOSE = docker compose` (no `-p`) when `INSTANCE=1`, and `COMPOSE = docker compose -p backend-N` for N≥2.

**Rationale:** e2e scripts call `docker compose ps/down/up` with no project flag, which targets the default project (`backend`). If INSTANCE=1 used `-p backend-1`, those scripts would silently operate on the wrong project. Using the default project for INSTANCE=1 is the only way to stay compatible without touching the e2e scripts.

**Implication:** INSTANCE=1's internal network must be named `backend_default` (Docker's default naming convention: `<project>_<network-key>`). INSTANCE≥2 networks are `backend-N`.

---

### Decision 4: External shared `traefik_net` Docker network, created by Makefile

**Chosen:** `traefik_net` is declared as `external: true` in `docker-compose.yaml` and created with `docker network create traefik_net 2>/dev/null || true` in a Makefile prerequisite target (`ensure-traefik-net`).

**Rationale:** All compose projects (INSTANCE 1..N) need to share this network. Declaring it as `external` means no single project "owns" it and it survives individual `docker compose down` calls. The idempotent create command handles both first-run and already-exists cases. The migration script needs the same guard since it calls `docker compose up` directly.

---

### Decision 5: INSTANCE≥2 excludes `traefik` from its started services

**Chosen:** `SERVICES` variable in Makefile is empty (all services) for INSTANCE=1, and explicitly lists `app collector mongo postgres redis alloy` for INSTANCE≥2.

**Rationale:** Only one Traefik container can bind host port 80. INSTANCE≥2 stacks contribute their `app` to `traefik_net` for Docker-provider routing but must not start another Traefik container.

---

### Decision 6: Volume path namespacing via `INSTANCE_SUFFIX`

**Chosen:** Volume bind-mount paths use `${VOLUME_PATH:-/tmp}/mongo-data${INSTANCE_SUFFIX:-}`. INSTANCE=1 → `INSTANCE_SUFFIX=""` (empty, preserves existing `/tmp/mongo-data` path). INSTANCE≥2 → `INSTANCE_SUFFIX=-N`.

**Rationale:** Named Docker volumes would change the current setup too much. Bind mounts with a suffix are the minimal diff that prevents DB data collision while keeping INSTANCE=1's existing paths unchanged.

---

### Decision 7: Per-instance Alloy with instance-specific tenant ID

**Chosen:** Each instance (including INSTANCE=1) has its own Alloy container. The Alloy domain is `${ALLOY_DOMAIN}-${INSTANCE:-1}` and tenant ID is `${ALLOY_DOMAIN}-${ALLOY_STAGE}-${INSTANCE:-1}`. INSTANCE=1 preserves existing values (via `INSTANCE_SUFFIX` empty).

**Rationale:** Each instance represents an independent environment and should ship metrics/logs under a distinct tenant identity. Sharing one Alloy across instances would mix telemetry from different stacks.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| `docker network create traefik_net` missing in migration test path | Added as one-liner guard in `01-start-blue.sh` before `docker compose up` |
| `container_name: app` removal breaks `deploy.sh` DNS resolution | `deploy.sh` uses `http://app:3000` which resolves via Docker's service-name DNS, not container_name. Blue-green swap uses `docker run --name app` (not compose), so compose's `container_name` was never load-bearing for `deploy.sh` |
| INSTANCE≥2 `app` label router names must be unique across all instances | Labels use `app-${INSTANCE:-1}` for both router and service names, ensuring uniqueness |
| `make dev-start 2` positional arg handling in root Makefile catches all numeric targets | Added `%: @:` catch-all to absorb unrecognized targets silently |

## Migration Plan

1. Create `traefik_net` manually once on dev machines (or let `make dev-start` do it automatically)
2. Run `make dev-stop` to tear down any existing INSTANCE=1 stack
3. Pull/rebuild backend image
4. Run `make dev-start 1` — validates backward-compat path
5. Run `make dev-start 2` — validates new multi-instance path
6. Run `make e2e-test` and `make migration-test` to confirm CI compatibility

**Rollback:** Revert the five changed files. The `traefik_net` network can be removed with `docker network rm traefik_net` (after all stacks are stopped) with no lasting side-effects.

**Note on `dev-stop-all` / `dev-obs-stop`:** These targets are intended for test environments and observability setup. Normal dev usage uses `make dev-start` and `make dev-stop`. `dev-obs-start` is a convenience shortcut that runs `make dev-start 1 && make dev-start 2 && make dev-start 3`. `dev-obs-stop` delegates to `dev-stop-all`.

## Open Questions

- Should `dev-stop-all` also remove the `traefik_net` network? (Current plan: no — network removal requires all connected containers to be stopped first, adding fragility; acceptable since `dev-stop-all` is test-only)