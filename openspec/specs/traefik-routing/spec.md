### Requirement: Traefik serves as the sole HTTP entry point on port 80
Traefik SHALL listen on port 80 and forward all requests matching `PathPrefix("/")` to the currently configured upstream service. No other service SHALL bind port 80 on the host.

#### Scenario: Normal request routing
- **WHEN** an HTTP request arrives on port 80
- **THEN** Traefik SHALL proxy it to the URL defined in `traefik/dynamic/app.yml`

---

### Requirement: Dynamic routing config is reloaded without restart
Traefik SHALL be configured with `providers.file.directory` pointing to `traefik/dynamic/` and `watch: true`. Any change to files in that directory SHALL be detected and applied within 1 second, without restarting the Traefik container.

#### Scenario: Dynamic config file updated
- **WHEN** `traefik/dynamic/app.yml` is overwritten with a new upstream URL
- **THEN** Traefik SHALL route subsequent requests to the new upstream within 1 second

#### Scenario: Existing connections not dropped
- **WHEN** the dynamic config is reloaded mid-request
- **THEN** in-flight requests SHALL complete against the previous upstream

---

### Requirement: Static Traefik config disables dashboard in production
`traefik/traefik.yml` SHALL NOT enable the Traefik API or dashboard (i.e., `api.insecure` SHALL be false or absent).

#### Scenario: No dashboard exposure
- **WHEN** Traefik starts with `traefik.yml`
- **THEN** port 8080 (Traefik admin) SHALL NOT be exposed to the host

---

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

---

### Requirement: Canonical dynamic config points to blue container
In steady state (between deploys), `traefik/dynamic/app.yml` SHALL route traffic to `http://app:3000` via a service named `app-blue`.

#### Scenario: Steady-state routing
- **WHEN** no deploy is in progress
- **THEN** all requests SHALL be routed to `http://app:3000`

#### Scenario: Deploy-time routing
- **WHEN** `deploy.sh` updates `app.yml` to point to `app-new:3001`
- **THEN** Traefik SHALL route traffic to the green container until `app.yml` is restored to `app:3000` after the rename

---

### Requirement: Traefik static config enables Docker provider scoped to traefik_net
`traefik/traefik.yml` SHALL configure a `providers.docker` section alongside the existing `providers.file` section. The Docker provider SHALL set `exposedByDefault: false` and `network: traefik_net`, so only containers with explicit `traefik.enable=true` labels on the `traefik_net` network are discovered.

#### Scenario: Docker provider active alongside file provider
- **WHEN** Traefik starts with the updated `traefik.yml`
- **THEN** both the file provider (watching `traefik/dynamic/`) and the Docker provider (scoped to `traefik_net`) SHALL be active simultaneously

#### Scenario: Containers without traefik.enable=true are not exposed
- **WHEN** a container running on `traefik_net` does not have the label `traefik.enable=true`
- **THEN** Traefik SHALL NOT create a router or service for it
