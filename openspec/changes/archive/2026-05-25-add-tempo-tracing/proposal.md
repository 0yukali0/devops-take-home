## Why

The observability stack currently covers metrics and alerting via kube-prometheus-stack but has no distributed tracing backend. Adding Grafana Tempo gives the devbox a complete observability picture (metrics + traces) and enables trace-to-metrics correlation within the existing Grafana instance.

## What Changes

- Add `tempo` as a Helm dependency in `charts/Chart.yaml` using the `grafana-community` Helm repository (`https://grafana-community.github.io/helm-charts`)
- Configure Tempo with emptyDir storage, 1-day trace retention, and OTLP receiver (gRPC + HTTP) enabled
- Add a Grafana datasource that registers Tempo in the existing Grafana instance so traces are queryable from the Grafana UI
- Update `charts/Chart.lock` by running `helm dependency update`

## Capabilities

### New Capabilities

- `tempo-deployment`: Tempo tracing backend deployed as a Helm subchart in the monitoring namespace, with 1-day retention and OTLP ingestion enabled
- `grafana-tempo-datasource`: Grafana datasource configured to connect to the Tempo instance so traces are queryable in the Grafana UI

### Modified Capabilities

- `prometheus-stack`: `charts/values.yaml` gains a `tempo:` section; Grafana datasource sidecar is configured to auto-provision the Tempo datasource

## Impact

- `charts/Chart.yaml` — new dependency entry for `tempo` from `grafana-community`
- `charts/Chart.lock` — regenerated after `helm dependency update`
- `charts/values.yaml` — new `tempo:` block (storage emptyDir, 1-day retention, OTLP receiver); Grafana datasource provisioning config under `kube-prometheus-stack.grafana`
- No breaking changes to existing Prometheus/Alertmanager/Grafana behavior
- Requires network access to `https://grafana-community.github.io/helm-charts` to pull the chart
