# Spec: backend-otel-tracing

## Requirements

### Requirement: OTel SDK is initialized before any other module
`src/instrumentation.ts` SHALL initialize and start the OpenTelemetry Node.js SDK. The compiled output SHALL be loaded via `--require` before `src/index.ts` and `src/collector.ts` so that auto-instrumentation patches are applied before any database client module is first imported.

#### Scenario: SDK starts before MongoDB client is loaded
- **WHEN** the `app` service starts
- **THEN** the OTel SDK SHALL be active and patching MongoDB/pg/redis modules before the first connection is attempted

### Requirement: OTLP/gRPC exporter targets Alloy
`src/instrumentation.ts` SHALL configure an `OTLPTraceExporter` using gRPC protocol. The exporter endpoint SHALL be read from the `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable (no hardcoded hostname).

#### Scenario: Spans are forwarded to Alloy
- **WHEN** the backend handles an HTTP request
- **THEN** the resulting trace spans SHALL be exported via OTLP/gRPC to the endpoint configured by `OTEL_EXPORTER_OTLP_ENDPOINT`

### Requirement: Service name is configurable via environment variable
The OTel resource SHALL use the `OTEL_SERVICE_NAME` environment variable as the service name so that `app` and `collector` services appear as distinct services in Tempo.

#### Scenario: app service appears as ems-api in Tempo
- **WHEN** the `app` container is running with `OTEL_SERVICE_NAME=ems-api`
- **THEN** all spans from that container SHALL carry the resource attribute `service.name=ems-api`

#### Scenario: collector service appears as ems-collector in Tempo
- **WHEN** the `collector` container is running with `OTEL_SERVICE_NAME=ems-collector`
- **THEN** all spans from that container SHALL carry the resource attribute `service.name=ems-collector`

### Requirement: HTTP requests produce a root span
The Hono HTTP server SHALL produce a root span for each inbound request, including span attributes for HTTP method, route, and status code.

#### Scenario: GET /api/devices generates a span
- **WHEN** a client calls `GET /api/devices`
- **THEN** Tempo SHALL contain a span with `http.method=GET` and a route attribute matching `/api/devices`

### Requirement: MongoDB operations produce child spans
Each MongoDB collection operation (find, insertOne, aggregate, etc.) in `src/index.ts` and `src/collector.ts` SHALL produce a child span nested under the parent HTTP or worker span.

#### Scenario: MongoDB find appears as child span
- **WHEN** `GET /api/devices` triggers `db.collection("devices").find({}).toArray()`
- **THEN** Tempo SHALL show a child span named after the MongoDB operation under the parent HTTP span

### Requirement: PostgreSQL queries produce child spans
Each `pgPool.query(...)` call in `src/index.ts` SHALL produce a child span nested under the parent HTTP span.

#### Scenario: PostgreSQL SELECT appears as child span
- **WHEN** `GET /api/dashboards` executes a PostgreSQL SELECT
- **THEN** Tempo SHALL show a child span for the database query under the parent HTTP span

### Requirement: Redis commands produce child spans
Each `redis.get(...)` call in `src/index.ts` SHALL produce a child span nested under the parent HTTP span.

#### Scenario: Redis GET appears as child span
- **WHEN** `GET /api/cache/:key` executes a Redis GET command
- **THEN** Tempo SHALL show a child span for the Redis command under the parent HTTP span

### Requirement: Span status is ERROR on database errors
When a MongoDB, PostgreSQL, or Redis operation throws an error (including connection failure), the active span's status SHALL be set to `ERROR`, the error message SHALL be set as the status description, and the exception SHALL be recorded on the span.

#### Scenario: MongoDB connection failure sets span ERROR
- **WHEN** MongoDB is unreachable and `getMongo()` throws
- **THEN** the active span SHALL have `status.code=ERROR` and a recorded exception event

#### Scenario: PostgreSQL query error sets span ERROR
- **WHEN** `pgPool.query(...)` throws
- **THEN** the active span SHALL have `status.code=ERROR` and a recorded exception event

### Requirement: Span status is OK on non-empty results
When a database operation succeeds and returns a non-empty result (array with at least one element, or a non-null single document/value), the active span's status SHALL be set to `OK`.

#### Scenario: MongoDB find with results sets span OK
- **WHEN** `db.collection("devices").find({}).toArray()` returns one or more documents
- **THEN** the active span SHALL have `status.code=OK`

#### Scenario: PostgreSQL query with rows sets span OK
- **WHEN** `pgPool.query(...)` returns one or more rows
- **THEN** the active span SHALL have `status.code=OK`

#### Scenario: Redis get with a value sets span OK
- **WHEN** `redis.get(key)` returns a non-null string
- **THEN** the active span SHALL have `status.code=OK`

### Requirement: Span status is UNSET on empty results
When a database operation succeeds but returns an empty result (empty array, zero rows, or null), no explicit span status SHALL be set (leave as `UNSET` default).

#### Scenario: MongoDB find with no documents leaves span UNSET
- **WHEN** `db.collection("devices").find({}).toArray()` returns an empty array
- **THEN** the active span SHALL have `status.code=UNSET` (no `setStatus` call made)

#### Scenario: Redis get with null value leaves span UNSET
- **WHEN** `redis.get(key)` returns `null`
- **THEN** the active span SHALL have `status.code=UNSET`

### Requirement: docker-compose passes OTel environment variables
`backend/docker-compose.yaml` SHALL set `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME` in the environment blocks of both the `app` and `collector` services.

#### Scenario: app service has OTel env vars
- **WHEN** a developer inspects `backend/docker-compose.yaml`
- **THEN** the `app` service environment SHALL include `OTEL_EXPORTER_OTLP_ENDPOINT` pointing to `alloy:4317` and `OTEL_SERVICE_NAME=ems-api`

#### Scenario: collector service has OTel env vars
- **WHEN** a developer inspects `backend/docker-compose.yaml`
- **THEN** the `collector` service environment SHALL include `OTEL_EXPORTER_OTLP_ENDPOINT` pointing to `alloy:4317` and `OTEL_SERVICE_NAME=ems-collector`
