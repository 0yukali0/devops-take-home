## 1. Helm Chart — Add Traefik Dependency

- [x] 1.1 Add Traefik Helm dependency (`name: traefik`, `version: "35.0.0"`, `repository: https://helm.traefik.io/traefik`) to `charts/Chart.yaml`
- [x] 1.2 Run `helm dependency update charts/` to download the Traefik chart into `charts/charts/`

## 2. Helm Values — Configure Traefik

- [x] 2.1 Add `traefik.deployment.kind: DaemonSet` to `charts/values.yaml`
- [x] 2.2 Add `traefik.tolerations` with the `node-role.kubernetes.io/control-plane:NoSchedule` toleration
- [x] 2.3 Add `traefik.nodeSelector: { node-role.kubernetes.io/control-plane: "" }` to `charts/values.yaml`
- [x] 2.4 Add `traefik.service.type: NodePort` to `charts/values.yaml`
- [x] 2.5 Configure `traefik.ports.web` with `exposedPort: 80` and `nodePort: 30080`
- [x] 2.6 Add `traefik.ports.tempo-grpc` with `port: 4317`, `exposedPort: 4317`, `nodePort: 30317`, `protocol: TCP`
- [x] 2.7 Disable `traefik.ports.websecure` (`expose.default: false`) in `charts/values.yaml`
- [x] 2.8 Enable `traefik.providers.kubernetesCRD: enabled: true` and disable `kubernetesIngress` in `charts/values.yaml`
- [x] 2.9 Disable the Traefik dashboard (`traefik.ingressRoute.dashboard.enabled: false`)

## 3. kind Cluster — Port Mappings

- [x] 3.1 Add `extraPortMappings` to the control-plane node in `docker/cluster.yaml`: host port 80 → container port 30080 (TCP) and host port 4317 → container port 30317 (TCP)

## 4. Helm Templates — Traefik CRD Resources

- [x] 4.1 Create `charts/templates/middleware.yaml` with a `Middleware` resource named `mimir-rewrite` in the `monitoring` namespace, using `spec.replacePath.path: /api/v1/push`
- [x] 4.2 Create `charts/templates/ingressroute.yaml` with an `IngressRoute` named `telemetry-http` in the `monitoring` namespace, routing `PathPrefix("/api/v1/write")` → Mimir distributor (port 8080) with the `mimir-rewrite` middleware, and `PathPrefix("/loki/api/v1/push")` → Loki (port 3100)
- [x] 4.3 Create `charts/templates/ingressroutetcp.yaml` with an `IngressRouteTCP` named `tempo-grpc` in the `monitoring` namespace, matching `HostSNI("*")` on the `tempo-grpc` entrypoint and routing to the Tempo service (port 4317)

## 5. Environment Configuration

- [x] 5.1 Add `ALLOY_REMOTE_HOST=127.0.0.1` to `backend/.env.example`
- [x] 5.2 Confirm Alloy's Docker Compose config uses `${ALLOY_REMOTE_HOST}` for all three remote endpoints (metrics, logs, traces) — update if any endpoint is hardcoded

## 6. Deploy & Validate

- [x] 6.1 Recreate the kind cluster: `make devbox-stop && make devbox-start`
- [x] 6.2 Deploy the updated Helm release: `helm upgrade --install metric-dashboard charts/ -n monitoring --create-namespace`
- [x] 6.3 Verify Traefik pod is running on the control-plane node: `kubectl get pods -n monitoring -l app.kubernetes.io/name=traefik -o wide`
- [x] 6.4 Verify NodePort bindings: `kubectl get svc -n monitoring metric-dashboard-traefik`
- [x] 6.5 Copy `backend/.env.example` → `backend/.env` and set `ALLOY_REMOTE_HOST=127.0.0.1`
- [x] 6.6 Start Docker Compose: `make dev-start`
- [x] 6.7 Smoke-test metrics: `curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1/api/v1/write -H "Content-Type: application/x-protobuf" --data-binary @/dev/null` — expect 204
- [x] 6.8 Smoke-test logs: `curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1/loki/api/v1/push -H "Content-Type: application/json" -d '{"streams":[]}'` — expect 204
- [x] 6.9 Verify traces appear in Grafana → Explore → Tempo datasource after Alloy has been running for ≥30 seconds
