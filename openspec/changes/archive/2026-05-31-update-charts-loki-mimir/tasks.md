## 1. Remove Alloy

- [x] 1.1 Remove the `alloy` dependency entry from `charts/Chart.yaml`
- [x] 1.2 Remove the `alloy:` values block from `charts/values.yaml`
- [x] 1.3 Delete `charts/templates/alloy-otlp-nodeport.yaml`
- [x] 1.4 Run `helm dependency update charts/` to drop the Alloy chart tarball from `charts/charts/`

## 2. Add Loki

- [x] 2.1 Add the `loki` dependency to `charts/Chart.yaml` with a pinned version from `https://grafana.github.io/helm-charts`
- [x] 2.2 Add a `loki:` values block in `charts/values.yaml` with `deploymentMode: SingleBinary`, single replica, `persistence.enabled: false`, and 24h retention
- [x] 2.3 Run `helm dependency update charts/` to pull the Loki chart tarball

## 3. Add Mimir

- [x] 3.1 Add the `mimir-distributed` dependency to `charts/Chart.yaml` with a pinned version from `https://grafana.github.io/helm-charts`
- [x] 3.2 Add a `mimir-distributed:` values block in `charts/values.yaml` with all component replicas set to 1, `minio.enabled: false`, local filesystem storage, and `blocks-retention-period: 24h`
- [x] 3.3 Run `helm dependency update charts/` to pull the Mimir chart tarball

## 4. Disable Prometheus

- [x] 4.1 Set `kube-prometheus-stack.prometheus.enabled: false` in `charts/values.yaml`
- [x] 4.2 Remove or update the `kube-prometheus-stack.prometheus.prometheusSpec` block since Prometheus is no longer deployed

## 5. Update Grafana Datasources

- [x] 5.1 Remove the existing Tempo datasource from `additionalDataSources` (it will be re-added in the correct order)
- [x] 5.2 Add a `Mimir` datasource of type `prometheus` pointing to `http://<release>-mimir-distributed-query-frontend.monitoring.svc.cluster.local:8080/prometheus`
- [x] 5.3 Add a `Loki` datasource of type `loki` pointing to `http://<release>-loki.monitoring.svc.cluster.local:3100`
- [x] 5.4 Retain the existing `Tempo` datasource entry in `additionalDataSources`

## 6. Verify

- [x] 6.1 Run `helm template charts/ --debug` and confirm no Alloy resources appear and Loki, Mimir resources are present
- [x] 6.2 Deploy with `helm upgrade --install` and confirm Loki and Mimir pods reach Running state
- [x] 6.3 Open Grafana and verify Mimir and Loki datasources are listed and return no connection errors
- [x] 6.4 Confirm no PersistentVolumeClaims are created for Loki or Mimir
