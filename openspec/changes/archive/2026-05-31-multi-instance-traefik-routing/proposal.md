## Why

The backend dev environment only supports one running instance at a time, blocking developers who need to test multiple versions or tenants side-by-side. This change enables `make dev-start <N>` to launch fully independent backend stacks, all routed through a single shared Traefik entry point, without breaking existing CI tests or the blue-green deploy workflow. It also provides `make dev-obs-start` as a convenience target to bring up 3 instances at once for observability testing, and `make dev-obs-stop` to tear everything down.

## What Changes

- `backend/traefik/traefik.yml` gains a Docker provider (`providers.docker`) alongside the existing file provider so Traefik can discover per-instance containers by label
- `backend/docker-compose.yaml`: `app` service gains Traefik Docker labels and joins the shared `traefik_net` network; `container_name: app` and host `ports` are removed; DB/cache volume paths gain an `INSTANCE_SUFFIX` variable to prevent data collisions
- `backend/Makefile` gains `dev-start`/`dev-stop` targets with `INSTANCE` support; INSTANCE=1 preserves the default compose project name for e2e/migration test compatibility; INSTANCE≥2 uses `-p backend-N` with isolated networks and volumes; new `dev-obs-start` and `dev-obs-stop` convenience targets start/stop 3 instances together
- Root `Makefile` is updated to forward positional `make dev-start 2` arguments as `INSTANCE=2` to the backend Makefile; also exposes `dev-obs-start` and `dev-obs-stop` at the root level
- `backend/scripts/migration/01-start-blue.sh` gets a `docker network create traefik_net` guard so the external network exists before `docker compose up`

## Capabilities

### New Capabilities

- `multi-instance-routing`: `make dev-start <N>` launches an isolated backend stack (app + DBs) reachable at `http://instance-N.localhost` via Traefik Docker provider labels; stacks share one Traefik container and one `traefik_net` Docker network; volumes are namespaced by instance number; `make dev-obs-start` starts instances 1–3 together; `make dev-obs-stop` stops all instances

### Modified Capabilities

- `traefik-routing`: Traefik now runs both a file provider (unchanged, used by CI and `deploy.sh`) and a Docker provider (new, used for per-instance label routing). The `app` service no longer exports port 3000 directly to the host.

## Impact

- `backend/traefik/traefik.yml` — static config change (add `providers.docker`)
- `backend/docker-compose.yaml` — service, network, and volume changes
- `backend/Makefile` — new targets: `dev-start`, `dev-stop`, `dev-obs-start`, `dev-obs-stop`, `dev-stop-all`, `ensure-traefik-net`; INSTANCE variable logic
- Root `Makefile` — positional arg forwarding; `dev-obs-start` and `dev-obs-stop` delegation
- `backend/scripts/migration/01-start-blue.sh` — one-line network guard
- No changes to `deploy.sh`, e2e scripts, migration scripts (02–cleanup), or CI workflow files
- Existing `http://localhost` routing via file provider is fully preserved; CI tests remain unaffected
