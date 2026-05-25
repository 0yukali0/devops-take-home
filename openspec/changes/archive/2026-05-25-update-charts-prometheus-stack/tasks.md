## 1. Update Chart.yaml

- [x] 1.1 Add `kube-prometheus-stack` as a dependency in `charts/Chart.yaml` with `repository: oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack` and a pinned version

## 2. Configure values.yaml

- [x] 2.1 Add `kube-prometheus-stack` section to `charts/values.yaml` with `prometheusOperator.enabled: true`, `prometheus.enabled: true`, `grafana.enabled: true`, `alertmanager.enabled: true`
- [x] 2.2 Configure Prometheus to use `emptyDir` storage (override `prometheus.prometheusSpec.storageSpec`)
- [x] 2.3 Configure Grafana to use `emptyDir` persistence (set `grafana.persistence.enabled: false` or `storageClassName: ""`)

## 3. Create charts/Makefile

- [x] 3.1 Create `charts/Makefile` with an `obs-deploy` target that runs `helm dependency build` if `Chart.lock` exists, otherwise `helm dependency update`
- [x] 3.2 Add `helm upgrade --install metric-dashboard . -n monitoring --create-namespace` as the install step in `obs-deploy`

## 4. Verify

- [x] 4.1 Run `helm dependency update` in `charts/` locally to confirm the OCI pull succeeds and `Chart.lock` is generated
- [x] 4.2 Run `make devbox-start` and confirm the `metric-dashboard` release appears in the `monitoring` namespace (`helm list -n monitoring`)
- [x] 4.3 Confirm all four component pods reach Running state (`kubectl get pods -n monitoring`)
