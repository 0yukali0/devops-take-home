## 1. Install Dependencies

- [x] 1.1 Add `@opentelemetry/sdk-node`, `@opentelemetry/auto-instrumentations-node`, `@opentelemetry/exporter-trace-otlp-grpc`, and `@opentelemetry/api` to `backend/package.json` via `pnpm add`

## 2. Create Instrumentation Entrypoint

- [x] 2.1 Create `backend/src/instrumentation.ts` that initializes `NodeSDK` with `getNodeAutoInstrumentations()` and an `OTLPTraceExporter` (gRPC) reading `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME` from environment
- [x] 2.2 Call `sdk.start()` at the end of `instrumentation.ts` so the SDK is active before any other module loads

## 3. Update Build and Dev Scripts

- [x] 3.1 Add `src/instrumentation.ts` as an explicit entry point in the `esbuild` `build` script in `backend/package.json` so `dist/instrumentation.js` is produced
- [x] 3.2 Prepend `--require ./dist/instrumentation.js` to the `start` script in `backend/package.json`
- [x] 3.3 Prepend `--require ./src/instrumentation.ts` to the `tsx` invocation in the `dev` script in `backend/package.json`

## 4. Add Explicit Span Status to Route Handlers

- [x] 4.1 Import `trace` and `SpanStatusCode` from `@opentelemetry/api` at the top of `backend/src/index.ts`
- [x] 4.2 Wrap each MongoDB call site (`GET /api/devices`, `GET /api/devices/:deviceId/telemetry`, `GET /api/telemetry/latest`, `POST /api/telemetry`) with span status logic: `OK` for non-empty results, `UNSET` for empty, `ERROR` + `recordException` on thrown errors
- [x] 4.3 Wrap the PostgreSQL call sites (`GET /api/dashboards`, `POST /api/dashboards`) with span status logic: `OK` for non-empty rows, `UNSET` for empty, `ERROR` + `recordException` on thrown errors
- [x] 4.4 Wrap the Redis call site (`GET /api/cache/:key`) with span status logic: `OK` for non-null value, `UNSET` for null, `ERROR` + `recordException` on thrown errors

## 5. Update docker-compose

- [x] 5.1 Add `OTEL_EXPORTER_OTLP_ENDPOINT=grpc://alloy:4317` and `OTEL_SERVICE_NAME=ems-api` to the `app` service environment block in `backend/docker-compose.yaml`
- [x] 5.2 Add `OTEL_EXPORTER_OTLP_ENDPOINT=grpc://alloy:4317` and `OTEL_SERVICE_NAME=ems-collector` to the `collector` service environment block in `backend/docker-compose.yaml`

## 6. Verify

- [x] 6.1 Rebuild the backend Docker image (`docker compose build app`) and confirm no TypeScript or build errors
- [x] 6.2 Restart services and confirm spans for `ems-api` appear in Tempo with MongoDB, PostgreSQL, and Redis child spans
- [x] 6.3 Confirm that a route returning no results shows a span with `UNSET` status and a route returning data shows `OK`
- [x] 6.4 Confirm that a simulated connection error produces a span with `ERROR` status and a recorded exception
