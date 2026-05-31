## ADDED Requirements

### Requirement: Traefik static config enables Docker provider scoped to traefik_net
`traefik/traefik.yml` SHALL configure a `providers.docker` section alongside the existing `providers.file` section. The Docker provider SHALL set `exposedByDefault: false` and `network: traefik_net`, so only containers with explicit `traefik.enable=true` labels on the `traefik_net` network are discovered.

#### Scenario: Docker provider active alongside file provider
- **WHEN** Traefik starts with the updated `traefik.yml`
- **THEN** both the file provider (watching `traefik/dynamic/`) and the Docker provider (scoped to `traefik_net`) SHALL be active simultaneously

#### Scenario: Containers without traefik.enable=true are not exposed
- **WHEN** a container running on `traefik_net` does not have the label `traefik.enable=true`
- **THEN** Traefik SHALL NOT create a router or service for it

## MODIFIED Requirements

### Requirement: docker-compose.yaml uses pre-built image, not build context
The `app` and `collector` services in `docker-compose.yaml` SHALL use an `image:` field referencing the artifact produced by `make image VERSION=<tag>`, with no `build:` directive. The `app` service SHALL NOT bind port 3000 directly on the host; instead it SHALL declare port 3000 via `expose` only, so all external access goes through Traefik.

#### Scenario: Compose up uses pre-built image
- **WHEN** `docker compose up -d` is run
- **THEN** Docker SHALL pull or reuse the locally tagged `backend:<VERSION>` image without rebuilding from source

#### Scenario: Traefik service included in Compose
- **WHEN** `docker compose up -d` is run
- **THEN** a Traefik container SHALL start, mounting `traefik/traefik.yml` and `traefik/dynamic/` from the host

#### Scenario: app service does not bind host port 3000
- **WHEN** `docker compose up -d` is run
- **THEN** port 3000 SHALL NOT be bound on the host; the `app` service SHALL be reachable only through Traefik
