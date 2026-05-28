## ADDED Requirements

### Requirement: All containers have explicit memory limits
Every service in `docker-compose.yaml` SHALL have a `mem_limit` set. No container SHALL be permitted to consume unbounded memory.

#### Scenario: Memory limits are defined for all services
- **WHEN** `docker compose config` is run
- **THEN** every service definition includes a `mem_limit` value

### Requirement: MongoDB memory is tuned for an 8 GB host
MongoDB SHALL be configured with `--wiredTigerCacheSizeGB 1.5` and a container `mem_limit` of `2g`. This leaves adequate memory for all other services on an 8 GB host.

#### Scenario: MongoDB container starts with correct cache setting
- **WHEN** `docker compose up` starts the mongo service
- **THEN** the mongod process runs with `--wiredTigerCacheSizeGB 1.5`

#### Scenario: Host is not in swap under normal load
- **WHEN** all containers are running with normal telemetry write load (35 docs/10 s)
- **THEN** host swap usage is zero or negligible

### Requirement: PostgreSQL is tuned with appropriate shared_buffers
PostgreSQL SHALL be configured with `shared_buffers=256MB` and `effective_cache_size=1GB` via the `POSTGRES_*` environment variables or command-line options.

#### Scenario: PostgreSQL starts with tuned shared_buffers
- **WHEN** `docker compose up` starts the postgres service
- **THEN** `SHOW shared_buffers` returns `256MB`

### Requirement: Redis has a memory cap with LRU eviction
Redis SHALL be configured with `maxmemory 256mb` and `maxmemory-policy allkeys-lru`. The container `mem_limit` SHALL be `512m`.

#### Scenario: Redis evicts old keys when memory limit is reached
- **WHEN** Redis memory usage approaches 256 MB
- **THEN** Redis evicts the least-recently-used keys to stay within the limit

### Requirement: Swap is disabled for containers
All containers with a `mem_limit` SHALL also have `memswap_limit` set to the same value as `mem_limit`, disabling swap for that container.

#### Scenario: Container is OOM-killed rather than swapping
- **WHEN** a container exceeds its `mem_limit`
- **THEN** the Docker OOM killer terminates the container; the process does NOT swap to disk
