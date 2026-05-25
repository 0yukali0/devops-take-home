## 1. Chart Dependency

- [x] 1.1 Add `tempo` dependency entry to `charts/Chart.yaml` with `repository: https://grafana-community.github.io/helm-charts`
- [x] 1.2 Run `helm dependency update charts/` to pull the Tempo chart and regenerate `charts/Chart.lock`

## 2. Tempo Values Configuration

- [x] 2.1 Add `tempo:` top-level block to `charts/values.yaml` with emptyDir storage configuration
- [x] 2.2 Set Tempo retention to `24h` in `charts/values.yaml`
- [x] 2.3 Enable OTLP gRPC (4317) and HTTP (4318) receivers in `charts/values.yaml`
- [x] 2.4 Set `tempo.grafana.enabled: false` in `charts/values.yaml` to disable the Tempo chart's built-in Grafana
- [x] 2.5 Configure NodePort Service in `charts/values.yaml`: gRPC port 4317 → NodePort 30317, HTTP port 4318 → NodePort 30318

## 3. Grafana Datasource

- [x] 3.1 Add `additionalDataSources` entry under `kube-prometheus-stack.grafana` in `charts/values.yaml` with type `tempo`, URL `http://metric-dashboard-tempo.monitoring.svc.cluster.local:3100`, and `isDefault: true`

## 4. Deploy and Verify

- [x] 4.1 Run `make obs-deploy` to apply the updated chart to the kind cluster
- [x] 4.2 Verify the Tempo pod is Running in the `monitoring` namespace
- [x] 4.3 Verify the Tempo NodePort Service exposes ports 30317 and 30318
- [x] 4.4 Open Grafana UI and confirm the Tempo datasource appears under Configuration → Data Sources
- [x] 4.5 Perform a Grafana datasource health check and confirm it passes
