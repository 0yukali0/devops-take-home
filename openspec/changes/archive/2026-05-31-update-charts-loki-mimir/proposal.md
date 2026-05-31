## Why

The observability umbrella chart currently lacks log aggregation and uses a local Prometheus storage model that doesn't scale well for multi-environment devbox usage. Alloy's role as a trace-forwarding pipeline adds operational overhead without adding value now that traces can be sent directly; replacing it with Loki (logs) and Mimir (metrics backend) rounds out the three pillars of observability with a consistent 24h retention policy.

## What Changes

- **Add** Loki Helm chart (single-binary mode) to the umbrella chart for log aggregation
- **Add** Mimir Helm chart (mimir-distributed) as a scalable metrics backend; configure Prometheus to remote-write to Mimir
- **Set** data retention to 24h across Loki and Mimir (matching existing Tempo retention)
- **Remove** Alloy subchart and its NodePort Service template (`charts/templates/alloy-otlp-nodeport.yaml`) — **BREAKING**
- **Add** Loki and Mimir as Grafana data sources alongside the existing Tempo datasource

## Capabilities

### New Capabilities
- `loki-single-binary`: Log aggregation via Loki in single-binary mode — receives logs, stores them locally, exposed as a Grafana datasource
- `mimir-metrics-backend`: Scalable metrics storage via Mimir; Prometheus remote-writes to Mimir, Grafana queries Mimir instead of Prometheus directly

### Modified Capabilities
- `alloy-otlp-pipeline`: Alloy is removed from the chart; NodePort 30317/30318 are decommissioned — callers must send OTLP traces directly to Tempo or use a sidecar

## Impact

- `charts/Chart.yaml`: Add `loki` and `mimir-distributed` dependencies; remove `alloy` dependency
- `charts/values.yaml`: Add Loki and Mimir values blocks; remove `alloy` block; add Loki + Mimir as `additionalDataSources` in Grafana
- `charts/templates/alloy-otlp-nodeport.yaml`: Deleted
- Downstream services relying on NodePort 30317/30318 (Alloy OTLP ingress) must update their OTLP endpoint to point directly at Tempo (`metric-dashboard-tempo.<namespace>.svc.cluster.local:4317`)
