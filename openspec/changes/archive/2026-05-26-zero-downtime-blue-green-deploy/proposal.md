## Why

The current deploy script stops all containers before starting new ones, causing a 30–60 second downtime window. This is unacceptable for a production service, and the existing approach also lacks safe database migration sequencing, risking data inconsistency if a migration fails mid-deploy.

## What Changes

- Add Traefik as a reverse proxy with file-based dynamic routing (`watch: true`) to enable hot-swap of upstream containers without signal restarts
- Add `migrate/index.js` — a standalone migration runner that builds a compound index and backfills a new field, both idempotently
- Replace the existing deploy script with `deploy.sh` implementing a full Blue-Green flow: pull → migrate → start green → healthcheck → switch Traefik → stop blue → rename
- Add `traefik/traefik.yml` (static config) and `traefik/dynamic/app.yml` (runtime-mutable routing config)
- Update `docker-compose.yaml` to include Traefik service and updated app configuration

## Capabilities

### New Capabilities

- `blue-green-deploy`: Zero-downtime deploy orchestration — runs migration, starts green container, health-probes it, switches Traefik routing, then removes the blue container
- `db-migration`: Idempotent MongoDB migration runner — creates compound index (non-blocking in MongoDB 7 hybrid mode) and backfills new fields in batches
- `traefik-routing`: Traefik-based dynamic HTTP routing with file provider hot-reload for seamless upstream switching

### Modified Capabilities

<!-- None — this is a greenfield addition to the deploy infrastructure -->

## Impact

- **Files added**: `backend/deploy.sh`, `backend/migrate/index.js`, `backend/traefik/traefik.yml`, `backend/traefik/dynamic/app.yml`
- **Files modified**: `backend/docker-compose.yaml`
- **Dependencies**: Traefik (Docker image), MongoDB 7 driver (Node.js `mongodb` package already in use)
- **Port layout**: Blue app on `:3000`, Green app on `:3001` during deploy window; Traefik on `:80`
- **Rollback**: If migration fails or green healthcheck times out, old container is never stopped — zero user impact
