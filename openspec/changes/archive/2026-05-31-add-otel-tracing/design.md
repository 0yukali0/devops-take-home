## Context

The backend is a Hono/TypeScript process (`ems-edge-simulator`) that connects to MongoDB (device/telemetry data), PostgreSQL (dashboard configs), and Redis (cache). Alloy already runs as a sidecar in `docker-compose.yaml` with an OTLP receiver on ports 4317 (gRPC) and 4318 (HTTP), and forwards spans to Tempo. No OTel SDK is present in the backend today — no spans are produced and therefore nothing appears in Tempo for backend operations.

All new implementation files are TypeScript (`.ts`); the existing `esbuild` build pipeline compiles them to `dist/`.

## Goals / Non-Goals

**Goals:**
- Initialize the OTel Node.js SDK once at startup, exporting via OTLP/gRPC to Alloy (`alloy:4317`)
- Produce spans for every MongoDB collection operation, PostgreSQL query, and Redis command
- Produce a root HTTP span for each inbound Hono request
- Apply explicit span status: `ERROR` on thrown errors/connection failures, `OK` on non-empty results, `UNSET` on empty results
- Pass `OTEL_EXPORTER_OTLP_ENDPOINT` through docker-compose so the exporter endpoint is configurable without code changes

**Non-Goals:**
- Modifying the Alloy `config.alloy` (already accepts OTLP)
- Adding custom business-logic spans beyond what auto-instrumentation covers
- Sampling configuration (default 100% is acceptable for this environment)
- Kubernetes chart changes

## Decisions

### 1. SDK initialization via `--require` preload

OTel must patch Node.js built-ins and third-party modules before they are first loaded. Embedding `NodeSDK.start()` inside `src/index.ts` after the `import { MongoClient }` statement is too late — the MongoDB driver is already loaded and cannot be patched.

**Decision**: Create `src/instrumentation.ts` (TypeScript) that initializes and starts the SDK. The compiled output `dist/instrumentation.js` is loaded via `--require ./dist/instrumentation.js` in the `start` script; for `dev` mode, `tsx` is invoked with `--require ./src/instrumentation.ts`.

**Alternative considered**: A top-of-file `import './instrumentation'` in `index.ts` — rejected because module import order is not guaranteed to run before transitive imports in all tsx/esbuild configurations, and `--require` is the officially recommended approach for Node.js OTel.

### 2. Auto-instrumentation via `@opentelemetry/auto-instrumentations-node`

This single package bundles all relevant instrumentations (`mongodb`, `pg`, `redis`, `http`, etc.) and activates only those whose target libraries are installed. It avoids manually listing individual instrumentation packages.

**Alternative considered**: Installing `@opentelemetry/instrumentation-mongodb`, `instrumentation-pg`, `instrumentation-redis-4` individually — rejected for extra package management with no architectural benefit at this stage.

### 3. OTLP/gRPC exporter targeting Alloy

Alloy is already present in `docker-compose.yaml` and accepts gRPC OTLP on port 4317. Sending directly to Alloy preserves the existing label-enrichment pipeline (DOMAIN/STAGE resource attributes) before traces reach Tempo.

**Alternative considered**: OTLP/HTTP exporter to Alloy port 4318 — both work; gRPC is preferred because the existing pipeline uses gRPC and has lower per-span overhead.

### 4. Explicit span status applied at each database call site in `index.ts`

Auto-instrumentation records DB spans but does not know the application-level semantics (empty result = UNSET, non-empty = OK). These status rules are applied directly at each `try/catch` block in `src/index.ts` using `@opentelemetry/api`:

```typescript
import { trace, SpanStatusCode } from "@opentelemetry/api";

// In each route handler:
try {
  const result = await dbOperation();
  const span = trace.getActiveSpan();
  if (Array.isArray(result) ? result.length > 0 : result != null) {
    span?.setStatus({ code: SpanStatusCode.OK });
  }
  // else: leave UNSET (default — no explicit setStatus call)
  return result;
} catch (err) {
  const span = trace.getActiveSpan();
  span?.setStatus({ code: SpanStatusCode.ERROR, message: (err as Error).message });
  span?.recordException(err as Error);
  throw err;
}
```

**Alternative considered**: Custom OTel plugin/hook — over-engineered for the number of call sites.

### 5. Service name from environment variable

`OTEL_SERVICE_NAME` is set via docker-compose environment so each service (`app`, `collector`) reports a distinct service name in Tempo without hardcoding.

## Risks / Trade-offs

- **`--require` with esbuild bundling**: esbuild must include `src/instrumentation.ts` as an explicit entry point so `dist/instrumentation.js` exists at the expected path. If omitted the preload silently fails.  
  → Mitigation: add `src/instrumentation.ts` to the `esbuild` entry points in the `build` script.

- **tsx dev mode**: `tsx --require` registers the TypeScript file via its CJS loader; confirm the flag is `--require` (not `--loader`) in the installed tsx version.  
  → Mitigation: alternatively use `NODE_OPTIONS="--require ./src/instrumentation.ts"` as an env-var approach.

- **Empty-result status on aggregation pipelines**: MongoDB aggregation returns an array (possibly empty). The `OK`/`UNSET` heuristic checks `Array.isArray(result) ? result.length > 0 : result != null`. All existing call sites already call `.toArray()` so the result is always a materialised array.  
  → Mitigation: document the pattern in spec requirements.

## Migration Plan

1. Install OTel packages (`pnpm add` in `backend/`)
2. Create `src/instrumentation.ts`
3. Update `package.json` build and dev scripts with `--require`
4. Add `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME` to docker-compose `app` and `collector` environment blocks
5. Rebuild image and restart services
6. Verify spans appear in Tempo by querying for the service name

**Rollback**: remove `--require` flag from scripts and the environment vars; no data migration needed.

## Open Questions

- Should `collector.ts` also be instrumented? It uses MongoDB but no HTTP. Assumption: yes, using `OTEL_SERVICE_NAME=ems-collector` so its DB spans are distinguishable in Tempo.
