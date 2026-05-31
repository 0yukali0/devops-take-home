## Why

Alloy (running in Docker Compose) currently needs separate host-port bindings for Mimir, Loki, and Tempo, creating fragmented configuration and tight coupling between the Docker Compose stack and the kind cluster's NodePort layout. By placing Traefik inside the kind cluster as a single HTTP + TCP gateway, all three telemetry pipelines can converge on one address (`127.0.0.1`), eliminating per-service port management and enabling Alloy's remote endpoints to be configured with a single `ALLOY_REMOTE_HOST` variable.

## What Changes

- Add Traefik Helm dependency to `charts/Chart.yaml` and configure it in `charts/values.yaml` as a DaemonSet tolerated on the control-plane node with two entrypoints: `web` (port 80 → NodePort 30080) and `tempo-grpc` (port 4317 → NodePort 30317).
- Add `extraPortMappings` to `docker/cluster.yaml` so the kind control-plane container exposes host ports 80 and 4317 to the matching NodePorts.
- Add `charts/templates/middleware.yaml`: a Traefik `Middleware` that rewrites `/api/v1/write` → `/api/v1/push` for Mimir's distributor endpoint.
- Add `charts/templates/ingressroute.yaml`: an `IngressRoute` routing `/api/v1/write` → Mimir distributor and `/loki/api/v1/push` → Loki.
- Add `charts/templates/ingressroutetcp.yaml`: an `IngressRouteTCP` with `HostSNI(*)` passing gRPC straight through to Tempo on port 4317.
- Update `backend/.env.example` to set `ALLOY_REMOTE_HOST=127.0.0.1`.

## Capabilities

### New Capabilities

- `traefik-k8s-telemetry-gateway`: Traefik deployed inside the monitoring namespace routes all three telemetry signal types (metrics HTTP, logs HTTP, traces gRPC) from a single host address to their respective backends (Mimir, Loki, Tempo) with path-based HTTP routing and TCP passthrough.

### Modified Capabilities

<!-- No existing spec-level requirements are changing. -->

## Impact

- **`docker/cluster.yaml`**: kind cluster must be recreated (`make devbox-stop && make devbox-start`) for `extraPortMappings` to take effect.
- **`charts/Chart.yaml` + `charts/values.yaml`**: Traefik Helm chart added as a dependency; `helm dependency update` required.
- **New Helm templates**: `middleware.yaml`, `ingressroute.yaml`, `ingressroutetcp.yaml` deployed into the `monitoring` namespace.
- **`backend/.env.example`**: documents the simplified `ALLOY_REMOTE_HOST=127.0.0.1` convention.
- **Traefik CRDs**: `IngressRoute`, `IngressRouteTCP`, and `Middleware` CRDs must be present (installed automatically via the Traefik Helm chart).
- No application code changes; no breaking changes to the Alloy config beyond the remote host value.
