## Context

The devbox observability stack is an umbrella Helm chart (`charts/`) that deploys `kube-prometheus-stack` (Prometheus, Grafana, AlertManager) into a `kind` cluster. Traces are currently not collected or visualised. Grafana Tempo is the natural fit because it integrates tightly with the existing Grafana instance and requires no additional storage backend for a single-node devbox.

The grafana-community Helm chart (`https://grafana-community.github.io/helm-charts`, chart: `tempo`) wraps the upstream Tempo single-binary and is the maintained community distribution referenced by the user's requirement.

## Goals / Non-Goals

**Goals:**
- Deploy Tempo single-binary via the grafana-community Helm chart as a subchart of the umbrella chart
- Disable Tempo chart's own Grafana instance (use the existing kube-prometheus-stack Grafana)
- Enable OTLP gRPC (4317) and HTTP (4318) receivers so applications can push traces using the standard OpenTelemetry protocol
- Expose OTLP ports via NodePort so host-side instrumentation can reach Tempo without `kubectl port-forward`
- Retain traces for 1 day (devbox storage is ephemeral; longer retention provides no value)
- Auto-provision a Grafana datasource pointing at Tempo in the existing kube-prometheus-stack Grafana
- Keep storage emptyDir — no PersistentVolumeClaim required
- No changes to the kind cluster configuration

**Non-Goals:**
- Zipkin, Jaeger, or other receiver protocols
- Persistent trace storage across pod restarts
- Tempo distributed (microservices) mode
- TraceQL alerting rules or Tempo Ruler
- Modifying the kind cluster extra-port-mappings or cluster config

## Decisions

### 1. Helm chart source: grafana-community

**Decision**: Use `https://grafana-community.github.io/helm-charts` (chart: `tempo`).

**Rationale**: This is the chart explicitly requested. It ships the Tempo single-binary with sane defaults and is actively maintained.

### 2. Disable Tempo chart's built-in Grafana

**Decision**: Set `tempo.grafana.enabled: false` in `values.yaml`.

**Rationale**: The stack already has Grafana provided by kube-prometheus-stack. Running a second Grafana instance is wasteful and confusing. All visualisation will happen through the existing Grafana.

### 3. OTLP NodePort exposure

**Decision**: Configure a NodePort Service for Tempo's OTLP ports (gRPC 4317, HTTP 4318). Use fixed NodePorts 30317 (gRPC) and 30318 (HTTP) to keep them stable across pod restarts. The kind cluster configuration remains untouched.

**Rationale**: The user explicitly requested NodePort. In a `kind` cluster, NodePort services are reachable from the host via the node IP (typically `localhost` when using Docker's default networking). No kind cluster config change is needed — standard NodePort access works out of the box.

**Alternative considered**: ClusterIP + `kubectl port-forward` — rejected per user requirement.

### 4. Grafana datasource provisioning

**Decision**: Use `kube-prometheus-stack.grafana.additionalDataSources` to inject a Tempo datasource directly in `values.yaml`.

**Rationale**: The simplest approach that avoids managing a separate ConfigMap. kube-prometheus-stack passes `additionalDataSources` directly to the Grafana Helm subchart which renders them as provisioning config. No sidecar watcher needed; the datasource is set at deploy time.

**Datasource URL**: `http://metric-dashboard-tempo.monitoring.svc.cluster.local:3200` (Helm release `metric-dashboard` + chart name `tempo`; port 3200 is the Tempo HTTP API port).

### 5. Retention configuration

**Decision**: Set Tempo's retention to 24h via the appropriate Tempo config field.

**Rationale**: emptyDir storage is ephemeral; 24 h is sufficient for a devbox trace workflow and prevents unbounded disk usage.

## Risks / Trade-offs

- **emptyDir data loss on pod restart** → Acceptable for a devbox; traces are ephemeral by design.
- **NodePort port conflicts** → Fixed ports 30317/30318 must not collide with other NodePort services. Mitigation: document in values comments.
- **Tempo service name depends on release name** → If the Helm release name changes from `metric-dashboard`, the datasource URL and NodePort service must be updated. Mitigation: comment in `values.yaml`.
- **grafana-community chart version** → Pinned in `Chart.lock` after `helm dependency update`; version bumps require a manual update cycle.

## Migration Plan

1. Add the `grafana-community` repo and `tempo` dependency to `charts/Chart.yaml`.
2. Add `tempo:` block to `charts/values.yaml`: emptyDir storage, 24h retention, OTLP receivers enabled, built-in Grafana disabled, NodePort service (30317/30318).
3. Add `kube-prometheus-stack.grafana.additionalDataSources` entry for Tempo in `charts/values.yaml`.
4. Run `helm dependency update charts/` to regenerate `Chart.lock`.
5. Re-deploy with `make obs-deploy`.

**Rollback**: Remove the `tempo` dependency and values block, re-run `helm dependency update`, re-deploy.

## Open Questions

- None — kind cluster is unchanged, NodePort ports 30317/30318 are agreed.
