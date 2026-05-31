## Why

The backend (`ems-edge-simulator`) has no distributed tracing: all MongoDB, PostgreSQL, and Redis interactions are invisible in Tempo even though Alloy is already running and forwarding spans. Adding OpenTelemetry SDK instrumentation closes this gap so engineers can trace slow queries, cascading failures, and error-prone database calls end-to-end.

## What Changes

- Add `@opentelemetry/sdk-node` and related instrumentation packages to the backend
- Initialize the OTel SDK at process startup, exporting spans via OTLP to the existing Alloy sidecar (port 4317/4318)
- Auto-instrument MongoDB, PostgreSQL (`pg`), and Redis (`redis`) client operations so each database call becomes a child span
- Auto-instrument the Hono HTTP server so each inbound request gets a root span
- Apply span status rules on all database-interaction spans:
  - `ERROR` + record exception when a connection failure or thrown error occurs
  - `OK` when the operation succeeds and returns a non-empty result
  - `UNSET` (default) when the operation succeeds but returns empty results

## Capabilities

### New Capabilities
- `backend-otel-tracing`: OpenTelemetry SDK setup, OTLP exporter wired to Alloy, database/HTTP auto-instrumentation, and explicit span status logic for the TypeScript backend

### Modified Capabilities

## Impact

- `backend/src/index.ts`: OTel SDK must be initialized before any other imports (requires a dedicated `instrumentation.ts` entrypoint or a `--require` preload)
- `backend/package.json`: New OTel npm packages added (`@opentelemetry/sdk-node`, `@opentelemetry/auto-instrumentations-node`, `@opentelemetry/exporter-trace-otlp-grpc`)
- `backend/docker-compose.yaml`: `app` and `collector` services need `OTEL_EXPORTER_OTLP_ENDPOINT` env var pointing to `alloy:4317`
- Alloy `config.alloy`: already receives OTLP on 4317/4318 and forwards to Tempo — no change needed
- No breaking changes to existing API contract or data schemas
