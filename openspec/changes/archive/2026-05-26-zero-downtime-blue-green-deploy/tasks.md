## 1. Docker Compose & Traefik Setup

- [x] 1.1 Remove `build: .` from `app` and `collector` services in `backend/docker-compose.yaml`; add `image: backend:${VERSION:-dev}` to each
- [x] 1.2 Add Traefik service to `backend/docker-compose.yaml` (image `traefik:v3`, port `80:80`, mount `./traefik/traefik.yml` and `./traefik/dynamic`)
- [x] 1.3 Create `backend/traefik/traefik.yml` with entrypoints on port 80 and file provider watching `dynamic/` directory
- [x] 1.4 Create `backend/traefik/dynamic/app.yml` with steady-state routing: router `app`, service `app-blue`, upstream `http://app:3000`
- [x] 1.5 Verify Traefik starts and proxies requests to `app:3000` via `docker compose up -d` using a locally tagged image

## 2. Database Migration

- [x] 2.1 Create `backend/migrate/index.js` with MongoDB connection using `process.env.MONGO_URI` (exit code 1 if missing)
- [x] 2.2 Implement index creation: `createIndex({ deviceId: 1, timestamp: -1 }, { name: "deviceId_timestamp_idx" })` on `telemetry` collection
- [x] 2.3 Implement batch backfill loop: `updateMany({ newField: { $exists: false } }, { $set: { newField: <default> } })` with batch size 1000, repeat until `modifiedCount === 0`
- [x] 2.4 Wrap all steps in try/catch; log error + stack to stderr and `process.exit(1)` on any failure
- [x] 2.5 Test migration idempotency: run twice against a test Mongo instance, confirm second run makes zero updates

## 3. Deploy Script

- [x] 3.1 Create `backend/deploy.sh` with argument validation: exit 1 with usage message if `$1` is missing
- [x] 3.2 Implement log function that writes `[ISO8601] <msg>` to stdout and to a timestamped log file
- [x] 3.3 Implement image existence check: `docker image inspect $IMAGE` — log error and exit 1 if missing, with hint to run `make image`
- [x] 3.4 Implement migration step: `docker run --rm --network backend_default -e MONGO_URI=... $IMAGE node migrate/index.js` — log failure and exit 1 on non-zero exit
- [x] 3.5 Implement green container start: `docker run -d --name app-new --network backend_default -p 3001:3000 -e MONGO_URI=... -e PG_URI=... $IMAGE`
- [x] 3.6 Implement health check loop: poll `curl -sf http://localhost:3001/health` every 3 seconds; auto-rollback (stop + rm `app-new`, log ROLLBACK, exit 1) after 60 seconds with no success
- [x] 3.7 Implement Traefik switch: write `traefik/dynamic/app.yml` atomically (write to temp, then `mv`) pointing to `app-new:3001` service
- [x] 3.8 Implement blue container removal: `docker stop app && docker rm app`
- [x] 3.9 Implement rename: `docker rename app-new app`
- [x] 3.10 Restore canonical Traefik config: rewrite `app.yml` to `app:3000`, log "Deploy complete"
- [x] 3.11 Make `deploy.sh` executable (`chmod +x`) and verify it runs end-to-end with a locally built image

## 4. Makefile Integration

- [x] 4.1 Add `deploy` target to `backend/Makefile`: `deploy.sh backend:$(VERSION)` (requires `VERSION` to be set)
- [x] 4.2 Add `migrate` target to `backend/Makefile` for running migration standalone (useful for debugging)

## 5. Validation

- [x] 5.1 Simulate migration failure: modify `migrate/index.js` temporarily to exit 1, run `deploy.sh` — confirm old container keeps serving and no `app-new` exists after
- [x] 5.2 Simulate healthcheck timeout: start a green container that never responds on `/health`, confirm auto-rollback fires within ~63 seconds and Traefik config is unchanged
- [x] 5.3 Full happy-path deploy: build two image tags (`make image VERSION=v1`, `make image VERSION=v2`), start v1, then run `deploy.sh backend:v2` — confirm zero dropped requests (use `watch curl localhost/health` or a simple loop)
- [x] 5.4 Confirm `docker compose up -d` no longer rebuilds from source (no build output; uses existing image tag)
