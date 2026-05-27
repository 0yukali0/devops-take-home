## 1. Credentials and Environment Setup

- [x] 1.1 Create `backend/.env.example` with placeholder keys: `MONGO_ROOT_USER`, `MONGO_ROOT_PASS`, `MONGO_APP_USER`, `MONGO_APP_PASS`, `MONGO_URI`
- [x] 1.2 Add `backend/.env` to `backend/.gitignore` (or root `.gitignore`)
- [x] 1.3 Create local `backend/.env` from `.env.example` with actual dev passwords

## 2. MongoDB Init Script

- [x] 2.1 Create directory `backend/mongo-init/`
- [x] 2.2 Write `backend/mongo-init/01-create-users.sh` that creates root user and app user (`readWrite` on `ems` db only) using `MONGO_INITDB_ROOT_USERNAME` / `MONGO_ROOT_PASS` env vars

## 3. docker-compose.yaml — MongoDB

- [x] 3.1 Change mongo `command` from `mongod --wiredTigerCacheSizeGB 4` to `mongod --auth --wiredTigerCacheSizeGB 1.5`
- [x] 3.2 Add `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` env vars to mongo service (from `.env`)
- [x] 3.3 Mount `backend/mongo-init/` to `/docker-entrypoint-initdb.d/` (read-only bind mount)
- [x] 3.4 Add named volume `mongo_data` mounted at `/data/db`
- [x] 3.5 Add `mem_limit: 2g` and `memswap_limit: 2g` to mongo service

## 4. docker-compose.yaml — PostgreSQL

- [x] 4.1 Add `POSTGRES_INITDB_ARGS` or command-line option to set `shared_buffers=256MB` and `effective_cache_size=1GB`
- [x] 4.2 Add named volume `postgres_data` mounted at `/var/lib/postgresql/data`
- [x] 4.3 Add `mem_limit: 1g` and `memswap_limit: 1g` to postgres service

## 5. docker-compose.yaml — Redis

- [x] 5.1 Add redis command: `redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru`
- [x] 5.2 Add named volume `redis_data` mounted at `/data`
- [x] 5.3 Add `mem_limit: 512m` and `memswap_limit: 512m` to redis service

## 6. docker-compose.yaml — App, Collector, Traefik

- [x] 6.1 Update `MONGO_URI` in app service to use credentials from `.env`: `mongodb://${MONGO_APP_USER}:${MONGO_APP_PASS}@mongo:27017/ems`
- [x] 6.2 Update `MONGO_URI` in collector service similarly
- [x] 6.3 Add `mem_limit: 512m` and `memswap_limit: 512m` to app service
- [x] 6.4 Add `mem_limit: 256m` and `memswap_limit: 256m` to collector service
- [x] 6.5 Add `mem_limit: 256m` and `memswap_limit: 256m` to traefik service

## 7. docker-compose.yaml — Named Volumes Block

- [x] 7.1 Add top-level `volumes:` block declaring `mongo_data`, `postgres_data`, `redis_data`

## 8. Fix MongoClient Leak in src/index.ts

- [x] 8.1 In `POST /api/telemetry` handler, replace `new MongoClient(env.MONGO_URI)` with a call to the existing `getMongo()` shared client
- [x] 8.2 Add `maxPoolSize: 10` option to the shared `MongoClient` constructor in `getMongo()`
- [x] 8.3 Remove the unreachable `insertClient.close()` comment and dead code

## 9. Verify

- [x] 9.1 Run `docker compose up -d --build` on a clean environment — confirm all services start
- [x] 9.2 Run `docker compose exec app node dist/seed.js` — confirm seed completes without auth errors
- [x] 9.3 Hit `GET /health`, `GET /api/devices`, `GET /api/telemetry/latest` — confirm 200 responses
- [x] 9.4 Run `docker stats` — confirm no service exceeds its `mem_limit` under normal load
- [x] 9.5 Run `docker compose down && docker compose up -d` — confirm MongoDB and Postgres data persists
