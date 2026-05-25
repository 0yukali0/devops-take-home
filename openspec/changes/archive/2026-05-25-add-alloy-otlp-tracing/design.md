## Context

The current observability umbrella chart deploys Tempo as the tracing backend, with its OTLP gRPC (4317) and HTTP (4318) ports exposed via a NodePort Service so host-side backends can ship traces directly. There is no intermediate collector, so traces arrive at Tempo with whatever attributes the sending application includes — no cluster-level enrichment is possible.

Grafana Alloy is the successor to Grafana Agent and ships as a Helm chart (`grafana/alloy`). Its configuration language (River/Alloy syntax) supports OTLP receiver and exporter components and an `otelcol.processor.attributes` processor for attaching static labels. Adding Alloy as a sidecar collector introduces a single enrichment point between backends and Tempo.

## Goals / Non-Goals

**Goals:**
- Insert Alloy as an OTLP pipeline stage: receive → enrich → forward to Tempo
- Attach a `cluster` resource attribute to every trace, sourced from a Helm value (`--set alloy.clusterName=<value>`)
- Keep NodePort 30317/30318 accessible for existing backends (re-target them to Alloy instead of Tempo)
- Tempo continues to receive traces over OTLP/gRPC, now from Alloy in-cluster

**Non-Goals:**
- Metrics or logs collection via Alloy (traces only)
- Alloy HA / clustering
- TLS between Alloy and Tempo
- Changing trace retention, storage backend, or sampling policy

## Decisions

### D1 — Use `alloy` Helm chart as a subchart dependency

**Decision**: Add `grafana/alloy` as a Helm dependency in `Chart.yaml`, configured via `alloy:` in `values.yaml`.

**Rationale**: Consistent with how Tempo and kube-prometheus-stack are managed. Alloy's chart provides a `configMap` with inline River config via `alloy.configMap.content`, giving full pipeline control without custom templates.

**Alternative considered**: Deploy Alloy as a separate `helm install` outside the umbrella chart — rejected because it splits operational concerns and breaks the single-chart deploy model.

### D2 — River config: otelcol.receiver.otlp → otelcol.processor.attributes → otelcol.exporter.otlp

**Decision**: Wire the Alloy pipeline using three River components:
1. `otelcol.receiver.otlp "default"` — listens on gRPC 4317 and HTTP 4318
2. `otelcol.processor.attributes "add_cluster"` — action `insert`, key `cluster`, value from a River `env()` or a hardcoded string sourced from a Helm templated value
3. `otelcol.exporter.otlp "tempo"` — forwards to `<release-name>-tempo.<namespace>.svc.cluster.local:4317` via gRPC

**Rationale**: This is the canonical Alloy tracing pipeline. The `otelcol.processor.attributes` component targets resource attributes, matching the OpenTelemetry semantic for cluster identity. Using a Helm-templated value in the River config (via `{{ .Values.alloy.clusterName }}`) avoids the need for a separate ConfigMap or environment variable injection.

**Alternative considered**: Use `otelcol.processor.resource` instead of `otelcol.processor.attributes` — both work; `attributes` with `resource: true` (or `resource` processor) is equally valid, but `attributes` with an insert action is simpler and well-documented.

### D3 — Re-target NodePort Service to Alloy, not Tempo

**Decision**: Update `charts/templates/tempo-otlp-nodeport.yaml` to select Alloy pods instead of Tempo pods for ports 30317/30318.

**Rationale**: Existing backends ship to `localhost:30317` / `localhost:30318`. Changing the NodePort target from Tempo to Alloy is transparent to backends while inserting the enrichment pipeline.

**Alternative considered**: Add a second NodePort for Alloy and keep the Tempo NodePort — rejected because it exposes Tempo's raw receiver externally, bypassing enrichment.

### D4 — `clusterName` as a required Helm value with a default

**Decision**: Add `alloy.clusterName: "default"` to `values.yaml` as the default, overridable at install time via `--set alloy.clusterName=prod`.

**Rationale**: A default prevents broken deployments when the value is omitted. Users override it per environment. The value is templated directly into the River config string inside `alloy.configMap.content`.

## Risks / Trade-offs

- **Alloy becomes a single point of failure for trace ingestion** → Mitigation: Alloy's chart defaults to `replicaCount: 1`; for dev/devbox this is acceptable. Production deployments should increase replicas.
- **River config is inlined as a Helm string** → Mitigation: Yaml multiline string (`|`) keeps it readable; any syntax error in the River config will fail Alloy startup visibly in pod logs.
- **Tempo NodePort selector change may briefly drop traces during rollout** → Mitigation: In devbox environments rolling restarts are instant; acceptable risk.
- **Alloy chart API may differ between versions** → Pin `alloy` chart version explicitly in `Chart.yaml`; check Alloy release notes before upgrading.

## Migration Plan

1. Run `helm dependency update charts/` to pull the Alloy chart
2. Deploy with `helm upgrade --install <release> charts/ --set alloy.clusterName=<env>`
3. Verify Alloy pod is Running and River config loaded (check pod logs for `config reloaded`)
4. Send a test trace to NodePort 30317 — confirm it appears in Tempo/Grafana with `cluster=<env>` attribute
5. **Rollback**: `helm rollback <release>` restores the previous chart version (Alloy removed, NodePort re-targets Tempo)

## Open Questions

- Should the Alloy OTLP receiver also expose an HTTP endpoint via NodePort (30318), or is gRPC-only (30317) sufficient for existing backends?
- Is `cluster` the right attribute key, or should it follow OTel semconv (`deployment.environment`, `k8s.cluster.name`)?
