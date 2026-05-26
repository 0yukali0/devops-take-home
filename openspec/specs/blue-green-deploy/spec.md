## ADDED Requirements

### Requirement: Deploy script accepts new image tag
`deploy.sh` SHALL accept a single positional argument `<new-image:tag>` and exit with a non-zero code if the argument is missing.

#### Scenario: Missing argument
- **WHEN** `deploy.sh` is invoked with no arguments
- **THEN** it SHALL print a usage message to stderr and exit with code 1

#### Scenario: Valid argument accepted
- **WHEN** `deploy.sh` is invoked with a valid image reference
- **THEN** it SHALL proceed to the pull step

---

### Requirement: Image must exist locally before deploy proceeds
The new image SHALL be built via `make image VERSION=<tag>` prior to invoking `deploy.sh`. `deploy.sh` SHALL verify the image exists locally using `docker image inspect` before starting any container mutation.

#### Scenario: Image exists locally
- **WHEN** `docker image inspect <image:tag>` exits with code 0
- **THEN** `deploy.sh` SHALL proceed to the migration step

#### Scenario: Image not found locally
- **WHEN** `docker image inspect <image:tag>` exits with a non-zero code
- **THEN** `deploy.sh` SHALL log an error message referencing `make image VERSION=<tag>` and exit with code 1, leaving all running containers untouched

---

### Requirement: Migration runs before green container starts
`deploy.sh` SHALL run the migration container to completion before starting the green (`app-new`) container.

#### Scenario: Migration succeeds
- **WHEN** the migration container exits with code 0
- **THEN** `deploy.sh` SHALL proceed to start the green container

#### Scenario: Migration fails
- **WHEN** the migration container exits with a non-zero code
- **THEN** `deploy.sh` SHALL log the failure and exit without starting the green container or modifying Traefik config

---

### Requirement: Green container health-probed before traffic switch
`deploy.sh` SHALL poll `GET /health` on `localhost:3001` every 3 seconds for up to 60 seconds before switching Traefik upstream.

#### Scenario: Green container passes health check
- **WHEN** `GET http://localhost:3001/health` returns HTTP 200 within 60 seconds
- **THEN** `deploy.sh` SHALL proceed to update the Traefik dynamic config

#### Scenario: Green container fails health check within timeout
- **WHEN** 60 seconds elapse without a successful health response
- **THEN** `deploy.sh` SHALL stop and remove the green container, log a ROLLBACK message, and exit without modifying the Traefik dynamic config

---

### Requirement: Traefik upstream switched atomically
`deploy.sh` SHALL update `traefik/dynamic/app.yml` to point to `app-new:3001` only after the green container passes health checks.

#### Scenario: Successful upstream switch
- **WHEN** the Traefik dynamic config is updated
- **THEN** Traefik SHALL detect the file change and route new requests to the green container within 1 second

---

### Requirement: Blue container removed after traffic switch
After Traefik is switched, `deploy.sh` SHALL stop and remove the blue (`app`) container.

#### Scenario: Blue container cleanup
- **WHEN** Traefik routing has been updated to the green container
- **THEN** `deploy.sh` SHALL run `docker stop app && docker rm app`

---

### Requirement: Green container renamed to canonical name
`deploy.sh` SHALL rename the green container from `app-new` to `app` after removing the blue container.

#### Scenario: Rename after blue removal
- **WHEN** the blue container has been removed
- **THEN** `deploy.sh` SHALL run `docker rename app-new app` so the next deploy starts from a known state

---

### Requirement: Traefik config restored to canonical naming after rename
After the rename, `deploy.sh` SHALL update `traefik/dynamic/app.yml` to reflect the canonical `app:3000` upstream.

#### Scenario: Config restored
- **WHEN** `app-new` has been renamed to `app`
- **THEN** `deploy.sh` SHALL rewrite `app.yml` to use `app:3000` as the upstream

---

### Requirement: Deploy script emits timestamped logs
Every significant step SHALL be logged with an ISO 8601 timestamp to a log file and to stdout.

#### Scenario: Step logging
- **WHEN** any deploy step starts or completes (pull, migrate, start, healthcheck, switch, stop, rename)
- **THEN** a line with format `[YYYY-MM-DDTHH:MM:SS] <message>` SHALL be appended to the log file
