## ADDED Requirements

### Requirement: MongoDB data is persisted across container restarts
MongoDB SHALL mount a named Docker volume to `/data/db`. Data SHALL survive `docker compose down` and `docker compose up` cycles.

#### Scenario: MongoDB data persists after container restart
- **WHEN** `docker compose down` is run followed by `docker compose up`
- **THEN** all previously inserted documents are still accessible

#### Scenario: Volume is defined as a named volume
- **WHEN** `docker compose config` is inspected
- **THEN** the mongo service uses a named volume (not a bind mount) for `/data/db`

### Requirement: PostgreSQL data is persisted across container restarts
PostgreSQL SHALL mount a named Docker volume to `/var/lib/postgresql/data`. Data SHALL survive container restarts.

#### Scenario: PostgreSQL data persists after container restart
- **WHEN** `docker compose down` is run followed by `docker compose up`
- **THEN** the `dashboards` table and all rows are still present

#### Scenario: Volume is defined as a named volume
- **WHEN** `docker compose config` is inspected
- **THEN** the postgres service uses a named volume (not a bind mount) for `/var/lib/postgresql/data`

### Requirement: Redis data directory uses a named volume
Redis SHALL mount a named Docker volume to `/data`. This protects cache data from accidental deletion via `docker compose down -v` is not issued without intent.

#### Scenario: Redis volume is declared
- **WHEN** `docker compose config` is inspected
- **THEN** the redis service has a named volume mounted at `/data`

### Requirement: All named volumes are declared in the top-level volumes block
All named volumes used by services SHALL be declared in the top-level `volumes:` section of `docker-compose.yaml`.

#### Scenario: Top-level volumes block contains all service volumes
- **WHEN** `docker compose config` is parsed
- **THEN** every named volume referenced by a service appears in the top-level `volumes:` block
