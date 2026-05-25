## 1. Add Alloy Helm Dependency

- [x] 1.1 Add `alloy` dependency entry to `charts/Chart.yaml` with version pinned and repository `https://grafana.github.io/helm-charts`
- [x] 1.2 Run `helm dependency update charts/` to fetch the Alloy chart and update `charts/Chart.lock`

## 2. Configure Alloy River Pipeline in values.yaml

- [x] 2.1 Add `alloy.clusterName: "default"` to `charts/values.yaml`
- [x] 2.2 Add `alloy.alloy.configMap.content` to `charts/values.yaml` with a River config that wires: `otelcol.receiver.otlp` → `otelcol.processor.attributes` (insert `cluster` from `{{ .Values.alloy.clusterName }}`) → `otelcol.exporter.otlp` (target: Tempo in-cluster gRPC)
- [x] 2.3 Confirm the River config Helm template renders correctly with `helm template charts/ --set alloy.clusterName=test` and inspect the Alloy ConfigMap output

## 3. Update NodePort Service to Target Alloy

- [x] 3.1 Update `charts/templates/tempo-otlp-nodeport.yaml` — rename to `alloy-otlp-nodeport.yaml` (or update in place) and change the selector to match Alloy pods (`app.kubernetes.io/name: alloy`)
- [x] 3.2 Verify selector labels match what the Alloy chart sets on its pods (check `helm template charts/ | grep -A10 "kind: Deployment"` for Alloy pod labels)

## 4. Verify Tempo Receiver Config

- [x] 4.1 Confirm `charts/values.yaml` still has Tempo's OTLP gRPC receiver enabled on port 4317 (no change needed unless Alloy uses a different port for the exporter)

## 5. End-to-End Validation

- [x] 5.1 Deploy the updated chart: `helm upgrade --install <release> charts/ -n monitoring --set alloy.clusterName=devbox`
- [x] 5.2 Confirm Alloy pod is Running and logs show `config reloaded` (no River parse errors)
- [x] 5.3 Send a test trace to `localhost:30317` (OTLP/gRPC) and verify it appears in Grafana Tempo with attribute `cluster=devbox`
- [x] 5.4 Send a test trace to `localhost:30318` (OTLP/HTTP) and verify it appears in Grafana Tempo with attribute `cluster=devbox`
