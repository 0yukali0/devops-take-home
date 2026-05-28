## Why

The current Docker Compose stack runs MongoDB with a 4 GB WiredTiger cache on an 8 GB host shared with App, Postgres, Redis, and OS — causing the host to swap and degrade performance. Additionally, there are no container memory limits, no data persistence (volumes), and MongoDB runs without authentication, making the stack unsafe and unreliable for production.

## What Changes

- Reduce MongoDB `wiredTigerCacheSizeGB` from 4 → 1.5 to free memory for other services
- Add Docker `mem_limit` to all containers (mongo, postgres, redis, app, collector, traefik)
- Enable MongoDB authentication (`--auth`) with a dedicated app user (least-privilege)
- Mount named volumes for MongoDB (`/data/db`), PostgreSQL (`/var/lib/postgresql/data`), and Redis (`/data`) to persist data across restarts
- Tune PostgreSQL `shared_buffers` from 128 MB → 256 MB and set `effective_cache_size = 1GB`
- Set Redis `maxmemory 256mb` with `allkeys-lru` eviction policy
- Inject credentials via `.env` file (not hardcoded in compose); add `.env` to `.gitignore`
- Fix connection leak in `POST /api/telemetry` (new MongoClient per request, never closed)

## Capabilities

### New Capabilities

- `mongo-auth`: MongoDB authentication enabled with root + app-scoped user, credentials injected via env
- `container-resource-limits`: All containers have explicit memory limits and swap constraints matching the 8 GB host budget
- `data-persistence`: Named volumes for MongoDB, PostgreSQL, and Redis ensure data survives container restarts

### Modified Capabilities

- `traefik-routing`: No spec-level behavior changes; only resource limit added

## Impact

- **docker-compose.yaml**: All services updated with limits, volumes, and env vars
- **backend/.env** (new): `MONGO_USER`, `MONGO_PASS`, `MONGO_URI` with credentials
- **backend/src/index.ts**: Fix `POST /api/telemetry` MongoClient leak; add explicit pool size limit
- **backend/mongo-init/**: Init script to create app user on first start
- Existing MongoDB data (if any) requires migration to add auth before switching to `--auth` mode
