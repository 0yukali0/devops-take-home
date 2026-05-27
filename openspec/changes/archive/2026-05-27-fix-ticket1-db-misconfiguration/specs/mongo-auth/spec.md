## ADDED Requirements

### Requirement: MongoDB requires authentication for all connections
MongoDB SHALL run with the `--auth` flag enabled. Unauthenticated connections to the `ems` database SHALL be rejected.

#### Scenario: App connects with valid credentials
- **WHEN** the app container starts with a valid `MONGO_URI` containing username and password
- **THEN** the connection is accepted and API endpoints return data normally

#### Scenario: Connection without credentials is rejected
- **WHEN** a client attempts to connect to MongoDB without providing credentials
- **THEN** the connection is refused with an authentication error

### Requirement: App user has least-privilege access
A dedicated MongoDB user SHALL be created with `readWrite` role scoped to the `ems` database only. The app user SHALL NOT have cluster-admin or root privileges.

#### Scenario: App user can read and write telemetry
- **WHEN** the app user connects and performs insert/find on the `telemetry` collection
- **THEN** the operations succeed

#### Scenario: App user cannot access admin database
- **WHEN** the app user attempts to access the `admin` database
- **THEN** the operation is rejected with an authorization error

### Requirement: User initialization is automated and idempotent
A `mongo-init` script placed in `/docker-entrypoint-initdb.d/` SHALL create the root and app users on first start. The script SHALL only run when the data directory is empty (i.e., on a fresh volume).

#### Scenario: First-time startup creates users automatically
- **WHEN** `docker compose up` is run against an empty MongoDB volume
- **THEN** root and app users are created without manual intervention

#### Scenario: Restart does not re-run init script
- **WHEN** MongoDB container is restarted with an existing data directory
- **THEN** the init script does not execute and existing users are preserved

### Requirement: Credentials are injected via environment variables
MongoDB credentials SHALL be stored in a `.env` file and injected into containers as environment variables. Credentials SHALL NOT be hardcoded in `docker-compose.yaml`.

#### Scenario: `.env` file is not committed to version control
- **WHEN** `.gitignore` is checked
- **THEN** `.env` is listed and excluded from commits

#### Scenario: `.env.example` documents required variables
- **WHEN** a developer clones the repo
- **THEN** `.env.example` exists with placeholder values for `MONGO_ROOT_USER`, `MONGO_ROOT_PASS`, `MONGO_APP_USER`, `MONGO_APP_PASS`
