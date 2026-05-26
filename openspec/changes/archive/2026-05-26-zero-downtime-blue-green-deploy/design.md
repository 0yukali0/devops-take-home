## Context

The backend service runs as a Docker Compose application with a single Node.js container (`app:3000`) and a MongoDB instance. Deployments currently use `docker compose down && docker compose up -d`, which creates a 30–60 second gap where no container serves traffic. There is no structured migration path for schema changes.

The stack is self-hosted (no Kubernetes), so rolling updates must be implemented manually at the shell level. The goal is a production-quality deploy script that requires no external orchestration tooling.

## Goals / Non-Goals

**Goals:**
- Zero downtime during deploy (no port gap, no dropped connections)
- Safe, ordered database migration before traffic switchover
- Automatic rollback if green container fails to become healthy within 60 seconds
- Migration is idempotent (safe to re-run on partial failure)
- Deploy script emits structured logs with timestamps

**Non-Goals:**
- Multi-replica load balancing (single active container per color)
- Kubernetes, Docker Swarm, or any cluster orchestration
- Automatic DB rollback — migrations are additive-only by policy
- TLS termination (out of scope for this change)
- Canary or weighted traffic splitting

## Decisions

### 1. Image built via `make image`, not inside docker-compose

**Decision:** Remove `build: .` from `docker-compose.yaml` for both `app` and `collector` services. Images are built separately using `make image VERSION=<tag>` (producing `backend:<tag>`). `deploy.sh` accepts a pre-built image reference.

**Rationale:** Decouples build from runtime. `make image` is the single, canonical build entrypoint. Removing `build:` from Compose avoids accidental rebuild on `docker compose up`, ensures the exact tested image is deployed, and aligns with CI/CD best practices where build and deploy are separate steps.

**Alternative considered:** Keep `build:` and call `docker compose build` in the deploy script — rejected because it rebuilds from local source, not the versioned artifact you want to deploy.

---

### 2. Traefik with file provider over nginx

**Decision:** Use Traefik with `providers.file.watch: true` rather than nginx.

**Rationale:** Switching upstreams with nginx requires sending `nginx -s reload`, which involves an extra shell command and brief config-parse delay. Traefik's file provider watches the dynamic config directory and hot-reloads within milliseconds on any change — the deploy script only needs to write a YAML file. This eliminates the need to exec into the Traefik container or send signals, making the switch atomic from the script's perspective.

**Alternative considered:** nginx with `nginx -s reload` — rejected because it requires executing a command inside the Traefik/nginx container, adds complexity, and the reload is not guaranteed to be instantaneous under load.

### 2. Pre-migration (migrate before starting green container)

**Decision:** Run migration to completion before starting the green container.

**Rationale:**
- MongoDB 7 uses hybrid index builds: the index is created non-blocking (only very short locks at start/end), so the old app continues serving during index creation.
- Backfill uses `{ $exists: false }` filter, so it's strictly additive and the old app ignores new fields.
- If migration fails, the old app is still running and the script exits — zero user impact.
- When the green container starts, the database is already in the expected state, avoiding startup failures due to missing indexes or data.

**Alternative considered:** Post-migration (migrate after switching traffic) — rejected because it would require the new app to handle a partially-migrated database, adding complexity and risk.

### 3. Blue-Green with fixed port slots (3000/3001)

**Decision:** Blue always runs on port 3000, green on 3001. After switchover, green is renamed to `app` (reclaiming port 3000 role) for the next deploy.

**Rationale:** Avoids dynamic port allocation. The Traefik dynamic config always knows which container name to target. Renaming after deploy means the next deploy always starts from the same known state.

**Alternative considered:** Dynamic port selection — rejected due to added complexity with no benefit in a single-host setup.

### 4. Healthcheck via HTTP probe loop (no Docker HEALTHCHECK)

**Decision:** Deploy script polls `GET /health` on `localhost:3001` every 3 seconds, with a 60-second total timeout.

**Rationale:** Docker's built-in `HEALTHCHECK` has configurable delays and intervals, but observing its state from a shell script requires polling `docker inspect`, which is less readable and harder to integrate with custom timeout logic. A simple `curl -sf` loop is explicit, portable, and easy to adjust.

## Risks / Trade-offs

- **Traefik file write race**: If `app.yml` is written with invalid YAML (e.g., partial write), Traefik may reload into a broken state. → Mitigation: Write to a temp file and `mv` atomically; optionally validate YAML with `python3 -c 'import yaml, sys; yaml.safe_load(sys.stdin)'` before moving.
- **60s healthcheck window too short**: If the app has a slow startup (JIT warmup, large cache init), it may time out. → Mitigation: The 60-second limit is configurable as a variable in `deploy.sh`. No user impact on timeout — rollback is automatic.
- **Post-switchover failure**: If the green container crashes after Traefik switches but within the same deploy run, the old container is already stopped. → Mitigation: Keep the old container name/image logged so an operator can run `deploy.sh <old-image>` to redeploy. Document this as out-of-scope for automatic recovery.
- **Migration additive-only policy**: Dropping or renaming fields in a migration would break the old app still serving traffic during migration. → Mitigation: Enforce by convention (documented) — this is standard for blue-green deploys.
- **Single Mongo instance**: No replica set means no read-from-secondary during index build; the primary bears full index build load. → Acceptable for current scale; index build is hybrid and non-blocking for reads/writes.

## Migration Plan

Deploy steps (executed by `deploy.sh <new-image:tag>`):
1. `docker pull <new-image>` — fail fast if image unavailable
2. Run migration container (`node migrate.js`) — exit on failure, old app unaffected
3. Start `app-new` on port 3001
4. Poll `GET /health` until pass or 60s timeout (auto-rollback on timeout)
5. Overwrite `traefik/dynamic/app.yml` to point to `app-new:3001`
6. `docker stop app && docker rm app`
7. `docker rename app-new app`
8. Restore `app.yml` to canonical `app:3000` naming

**Rollback strategy:**
- Before step 5: stop `app-new`, exit — old app continues serving
- After step 5: manual — run `deploy.sh <old-image:tag>`; migrations are additive-only so this is safe

## Open Questions

- Should the deploy script send a Slack/webhook notification on success or failure? (Not in scope for this change, but a natural follow-up.)
- Is `migrate.js` the canonical entrypoint name, or should it be configurable via an env var / Docker CMD override?
