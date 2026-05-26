## ADDED Requirements

### Requirement: Migration creates compound index non-blockingly
`migrate/index.js` SHALL create a compound index `{ deviceId: 1, timestamp: -1 }` named `deviceId_timestamp_idx` on the `telemetry` collection. MongoDB 7's default hybrid index build SHALL be used (non-blocking for reads and writes during build).

#### Scenario: Index does not exist
- **WHEN** `deviceId_timestamp_idx` does not exist on the `telemetry` collection
- **THEN** `createIndex` SHALL complete successfully and the migration SHALL proceed to the backfill step

#### Scenario: Index already exists
- **WHEN** `deviceId_timestamp_idx` already exists (idempotent re-run)
- **THEN** `createIndex` SHALL be a no-op and the migration SHALL proceed without error

---

### Requirement: Migration backfills missing field idempotently in batches
`migrate/index.js` SHALL update all `telemetry` documents where `newField` does not exist, setting it to a default value, processing at most 1000 documents per `updateMany` call.

#### Scenario: Documents without new field exist
- **WHEN** documents exist with `{ newField: { $exists: false } }`
- **THEN** the migration SHALL update them in batches until `modifiedCount === 0`

#### Scenario: All documents already have new field
- **WHEN** every document already has `newField`
- **THEN** the migration SHALL perform zero updates and exit with code 0

#### Scenario: Partial previous run
- **WHEN** some documents have `newField` and some do not (e.g., interrupted previous run)
- **THEN** only documents missing `newField` SHALL be updated; already-updated documents SHALL NOT be overwritten

---

### Requirement: Migration exits non-zero on any unhandled error
If any step fails (connection error, index build error, update error), `migrate/index.js` SHALL catch the error, log it with stack trace to stderr, and exit with code 1.

#### Scenario: MongoDB connection failure
- **WHEN** `MONGO_URI` is unreachable during connect
- **THEN** the migration SHALL log the error and exit with code 1

#### Scenario: Index build error
- **WHEN** `createIndex` throws
- **THEN** the migration SHALL log the error and exit with code 1

---

### Requirement: Migration reads connection string from environment
`migrate/index.js` SHALL use `process.env.MONGO_URI` as the MongoDB connection string. If the variable is absent or empty, it SHALL exit with code 1 before attempting any database operation.

#### Scenario: MONGO_URI is set
- **WHEN** `MONGO_URI` contains a valid connection string
- **THEN** the migration SHALL connect and execute

#### Scenario: MONGO_URI is missing
- **WHEN** `MONGO_URI` is undefined or an empty string
- **THEN** the migration SHALL print "MONGO_URI is required" to stderr and exit with code 1
