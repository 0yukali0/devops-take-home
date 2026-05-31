### Requirement: dev-start accepts an instance number argument
`make dev-start <N>` SHALL launch a fully isolated backend stack for instance N, where N is a positive integer. The stack SHALL include app, collector, MongoDB, PostgreSQL, Redis, and Alloy services. When N is omitted, it SHALL default to 1.

#### Scenario: Start instance 1 (default)
- **WHEN** `make dev-start` or `make dev-start 1` is run
- **THEN** the compose project SHALL use the default project name (`backend`) and all services SHALL start including Traefik

#### Scenario: Start instance 2
- **WHEN** `make dev-start 2` is run
- **THEN** a compose project named `backend-2` SHALL start with services `app collector mongo postgres redis alloy` (no Traefik, to avoid port 80 conflict)

#### Scenario: Seed data loaded after start
- **WHEN** `make dev-start <N>` completes
- **THEN** `node dist/seed.js` SHALL have run inside the instance's `app` container

---

### Requirement: Each instance is reachable at a unique subdomain via Traefik
The `app` service in each compose project SHALL be reachable at `http://instance-N.localhost` via Traefik Docker provider label routing, where N is the instance number.

#### Scenario: Instance 1 routed by Docker provider label
- **WHEN** a request arrives with `Host: instance-1.localhost`
- **THEN** Traefik SHALL proxy it to the INSTANCE=1 `app` container on port 3000 via `traefik_net`

#### Scenario: Instance 2 routed by Docker provider label
- **WHEN** a request arrives with `Host: instance-2.localhost`
- **THEN** Traefik SHALL proxy it to the INSTANCE=2 `app` container on port 3000 via `traefik_net`

#### Scenario: Legacy localhost routing unaffected
- **WHEN** a request arrives with no `Host` header override (plain `http://localhost`)
- **THEN** Traefik SHALL route it via the file provider to INSTANCE=1's `app` container, unchanged from pre-multi-instance behavior

---

### Requirement: Each instance joins the shared traefik_net network
The `app` service in every compose project SHALL join the external Docker network `traefik_net`. The `traefik` service (INSTANCE=1 only) SHALL also join `traefik_net`. All other services (MongoDB, PostgreSQL, Redis, Collector, Alloy) SHALL NOT join `traefik_net`.

#### Scenario: traefik_net created before compose up
- **WHEN** `make dev-start <N>` is run and `traefik_net` does not yet exist
- **THEN** the network SHALL be created automatically before compose starts

#### Scenario: traefik_net survives docker compose down
- **WHEN** `make dev-stop <N>` or `docker compose down` is run for any single instance
- **THEN** the `traefik_net` network SHALL NOT be removed, so other running instances remain routable

---

### Requirement: Volume paths are namespaced per instance to prevent data collision
MongoDB, PostgreSQL, and Redis bind-mount paths SHALL include an instance suffix. INSTANCE=1 SHALL use the existing paths (no suffix) for backward compatibility. INSTANCE≥2 SHALL use paths suffixed with `-N`.

#### Scenario: Instance 1 uses existing volume paths
- **WHEN** `make dev-start 1` is run
- **THEN** MongoDB data SHALL be at `${VOLUME_PATH:-/tmp}/mongo-data`, PostgreSQL at `${VOLUME_PATH:-/tmp}/postgres-data`, Redis at `${VOLUME_PATH:-/tmp}/redis-data`

#### Scenario: Instance 2 uses suffixed volume paths
- **WHEN** `make dev-start 2` is run
- **THEN** MongoDB data SHALL be at `${VOLUME_PATH:-/tmp}/mongo-data-2`, PostgreSQL at `${VOLUME_PATH:-/tmp}/postgres-data-2`, Redis at `${VOLUME_PATH:-/tmp}/redis-data-2`

---

### Requirement: Each instance has its own Alloy with an instance-specific tenant ID
Each instance's Alloy container SHALL be configured with a domain of `${ALLOY_DOMAIN}-N` and a tenant ID of `${ALLOY_DOMAIN}-${ALLOY_STAGE}-N`, where N is the instance number.

#### Scenario: Instance 1 Alloy uses base domain and tenant ID
- **WHEN** INSTANCE=1 Alloy starts
- **THEN** it SHALL use domain `${ALLOY_DOMAIN}-1` and tenant ID `${ALLOY_DOMAIN}-${ALLOY_STAGE}-1`

#### Scenario: Instance 2 Alloy uses suffixed domain and tenant ID
- **WHEN** INSTANCE=2 Alloy starts
- **THEN** it SHALL use domain `${ALLOY_DOMAIN}-2` and tenant ID `${ALLOY_DOMAIN}-${ALLOY_STAGE}-2`

---

### Requirement: INSTANCE=1 is fully backward-compatible with existing CI tests
Running `make dev-start` (without an instance number) SHALL produce behavior identical to the pre-multi-instance implementation: default compose project name, `backend_default` internal network, existing volume paths, and `http://localhost` routing via the file provider.

#### Scenario: e2e tests pass without INSTANCE argument
- **WHEN** `make e2e-test` runs (which calls `make dev-start` without INSTANCE)
- **THEN** all e2e test scripts SHALL pass, including scripts that call `docker compose ps/down/up` with no project flag

#### Scenario: Migration tests pass without INSTANCE argument
- **WHEN** `make migration-test` runs
- **THEN** all migration test scripts SHALL pass, including `01-start-blue.sh` which calls `docker compose up -d traefik ...`

---

### Requirement: dev-stop accepts an instance number argument
`make dev-stop <N>` SHALL stop and remove all containers for instance N without affecting other running instances.

#### Scenario: Stop instance 2 while instance 1 runs
- **WHEN** `make dev-stop 2` is run while instance 1 is running
- **THEN** the INSTANCE=2 compose project SHALL be torn down and instance 1 SHALL remain running and routable

---

### Requirement: dev-obs-start starts instances 1, 2, and 3 together
`make dev-obs-start` SHALL sequentially start instances 1, 2, and 3 by calling `make dev-start` for each. All three instances SHALL be running and routable via their respective subdomains after the command completes.

#### Scenario: All three instances started
- **WHEN** `make dev-obs-start` is run
- **THEN** instances 1, 2, and 3 SHALL all be running with `http://instance-1.localhost`, `http://instance-2.localhost`, and `http://instance-3.localhost` each returning a valid response

---

### Requirement: dev-obs-stop stops all running instances
`make dev-obs-stop` SHALL stop all backend instances (equivalent to `dev-stop-all`) without failing if a project is not running.

#### Scenario: All instances stopped
- **WHEN** `make dev-obs-stop` is run with instances 1, 2, and 3 active
- **THEN** all three compose projects SHALL be torn down and no containers from any instance SHALL remain running

---

### Requirement: dev-stop-all tears down all instances
`make -C backend dev-stop-all` SHALL attempt to stop compose projects for instances 1 through 5 and the default project, without failing if a project is not running. This target is intended for test environments only.

#### Scenario: Stop all when multiple instances running
- **WHEN** `make -C backend dev-stop-all` is run with instances 1, 2, and 3 active
- **THEN** all three compose projects SHALL be torn down and no containers from any instance SHALL remain running
