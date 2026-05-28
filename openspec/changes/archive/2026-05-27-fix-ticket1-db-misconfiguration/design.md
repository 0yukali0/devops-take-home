## Context

The EMS edge stack runs on an 8 GB / 50 GB Linux host. The current `docker-compose.yaml` has four production-blocking issues:

1. **Memory overcommit**: MongoDB is configured with `--wiredTigerCacheSizeGB 4`, consuming 50% of RAM before any other service starts. The host is actively swapping.
2. **No container limits**: Any service can grow unbounded and starve others; no blast-radius isolation.
3. **No data persistence**: No volume mounts — all MongoDB and PostgreSQL data is lost on `docker compose down`.
4. **No authentication**: MongoDB accepts connections from any client with no credentials.

A secondary bug in `src/index.ts` compounds the memory issue: `POST /api/telemetry` opens a new `MongoClient` per request and never closes it, leaking connections until the MongoDB pool is exhausted.

## Goals / Non-Goals

**Goals:**
- Eliminate swap by right-sizing all container memory limits to fit within 8 GB
- Ensure stateful data (MongoDB, PostgreSQL, Redis) survives container restarts via named volumes
- Enable MongoDB authentication with a least-privilege app user
- Improve PostgreSQL query performance by tuning `shared_buffers`
- Fix the `POST /api/telemetry` MongoClient connection leak

**Non-Goals:**
- MongoDB replica set or sharding (single-node is correct for edge sites)
- Redis Cluster or Sentinel
- Changing application API contracts or data models
- Full secrets management with Vault or SOPS (`.env` file is pragmatic for 12 isolated edge sites)
- Adding telemetry indexes (out of scope for this ticket)

## Decisions

### D1: Memory Budget — 1.5 GB WiredTiger cache, container limit 2 GB

WiredTiger's formula gives `max(50% × (RAM - 1 GB), 256 MB)` = 3.5 GB for an 8 GB host, but that assumes MongoDB owns the machine. With five other services sharing the host, 1.5 GB cache provides adequate working set for the telemetry access pattern (mostly recent inserts + time-range reads per device). The container limit is set 500 MB above the cache to absorb connection overhead, index structures, and WiredTiger journal writes.

| Service | `mem_limit` | Key tuning |
|---------|------------|------------|
| mongo | 2 g | `wiredTigerCacheSizeGB 1.5` |
| postgres | 1 g | `shared_buffers=256MB`, `effective_cache_size=1GB` |
| redis | 512 m | `maxmemory 256mb`, `allkeys-lru` |
| app | 512 m | `maxPoolSize: 10` on MongoClient |
| collector | 256 m | — |
| traefik | 256 m | — |
| OS reserve | ~1.5 GB | kernel, page cache, system daemons |

**Alternative considered:** 2 GB WiredTiger cache — rejected; leaves < 2 GB for Postgres + Redis + App + OS, which is insufficient.

### D2: MongoDB Authentication — `mongo-init` init script

Use the official `mongo:7` Docker image convention: place a shell script in `/docker-entrypoint-initdb.d/` to create the root and app users. Pass `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD` as environment variables. The init script runs **only on an empty data directory**, making it idempotent on restarts.

The app user is granted `readWrite` on the `ems` database only — no cluster-admin privileges.

**Alternative considered:** Manual `docker exec` + `db.createUser()` — rejected; not reproducible and breaks automation.

### D3: Credentials via `.env` file

Docker Secrets requires Swarm mode; this stack is plain Compose. For 12 isolated edge sites, a per-site `.env` file is the pragmatic choice: simple, auditable, and familiar. `.env.example` with placeholder values is committed; `.env` is in `.gitignore`.

### D4: Redis — named volume, `allkeys-lru`, no AOF

Redis is used as a session/cache store only. `allkeys-lru` is chosen as the eviction policy — it allows Redis to evict any key when memory pressure occurs, making it behave as a pure LRU cache. Enabling AOF would add sustained disk I/O on a host already write-heavy from 300 K MongoDB inserts/day; named volume provides sufficient durability for cache data.

### D5: Fix MongoClient leak — reuse shared client

Replace the per-request `new MongoClient()` in `POST /api/telemetry` (`index.ts:124`) with a call to the existing `getMongo()` shared client. Additionally, cap the MongoDB connection pool with `maxPoolSize: 10` to bound memory under high concurrency.

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| Reducing WiredTiger cache increases cache misses on large time-range queries | Acceptable trade-off; the primary concern is eliminating swap on the host |
| MongoDB auth migration on sites with existing data | Three-step migration documented in Migration Plan; fresh sites are unaffected |
| Container OOM kill mid-write for MongoDB | `restart: unless-stopped` + WiredTiger journal ensures crash recovery; limits have headroom to avoid OOM under normal load |
| `.env` accidentally committed | `.env` in `.gitignore`; `.env.example` documents required keys |
| `memswap_limit = mem_limit` disables swap for containers | Intentional — OOM kill is preferable to silent swap-induced degradation |

## Migration Plan

**Fresh environment (new site):**
1. Copy `.env.example` → `.env`, set `MONGO_ROOT_PASS` and `MONGO_APP_PASS`
2. `docker compose up -d --build`
3. Init script creates users automatically (runs once on empty data dir)
4. `docker compose exec app node dist/seed.js`

**Existing environment (live site with data):**
1. While MongoDB is running *without* `--auth`, exec in and create users manually
2. Update `.env` with the same credentials
3. `docker compose down` (volumes retain data)
4. Apply new compose config; `docker compose up -d`
5. Verify: `curl http://localhost:3000/health`

**Rollback:**
- Remove `--auth` from mongo command, revert `MONGO_URI` in `.env` to unauthenticated form
- Named volumes remain intact regardless of config rollback
