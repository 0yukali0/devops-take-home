## Context

The existing local dev stack runs Alloy inside Docker Compose and forwards telemetry to Mimir, Loki, and Tempo deployed inside a kind cluster. Today each backend is reachable on a distinct host port (Mimir `:9009`, Loki `:3100`, Tempo `:4317`), requiring Alloy's config to enumerate three separate remote endpoints and the kind cluster to expose three separate NodePorts. The goal is to consolidate these into a single address (`127.0.0.1`) behind Traefik acting as a K8s-native telemetry gateway.

Traefik is already a declared dependency for the blue-green deploy feature; this change redeploys it **inside the monitoring namespace in kind** (not on the Docker Compose host), using Helm to install it as a DaemonSet pinned to the control-plane node.

## Goals / Non-Goals

**Goals:**
- Alloy sends all three telemetry signal types to a single host address (`ALLOY_REMOTE_HOST=127.0.0.1`) on two ports (80 for HTTP, 4317 for gRPC).
- Traefik routes HTTP traffic by path: `/api/v1/write` → Mimir distributor (with path rewrite to `/api/v1/push`), `/loki/api/v1/push` → Loki.
- Traefik passes gRPC traffic through at the TCP level on port 4317 → Tempo.
- The solution is fully declarative (Helm values + templates); no manual `kubectl apply` steps beyond the normal `helm upgrade`.

**Non-Goals:**
- TLS termination or mTLS between Alloy and Traefik (dev environment; Alloy is configured `insecure = true`).
- Production-grade HA for Traefik (one DaemonSet pod on the control-plane is sufficient for local dev).
- Replacing the Traefik instance already configured in Docker Compose for the application blue-green deploy.

## Decisions

### D1: Traefik as DaemonSet on control-plane, not Deployment

**Decision:** Deploy Traefik as a `DaemonSet` with `nodeSelector: node-role.kubernetes.io/control-plane: ""` and a matching toleration.

**Rationale:** kind maps `extraPortMappings` to the control-plane container only. A Deployment could schedule on any worker node where the NodePort binding would not match the host port. DaemonSet + nodeSelector guarantees the Traefik pod lands on the control-plane node every time.

**Alternative considered:** Deploy a Deployment and use `hostNetwork: true`. Rejected because `hostNetwork` bypasses K8s service routing and conflicts with other services.

---

### D2: Two entrypoints — `web` (HTTP) and `tempo-grpc` (TCP)

**Decision:** Configure Traefik with a `web` entrypoint on port 80 (NodePort 30080) for HTTP path routing and a `tempo-grpc` entrypoint on port 4317 (NodePort 30317) for TCP passthrough.

**Rationale:** gRPC (HTTP/2 with binary framing) cannot be routed by Traefik's HTTP layer using `IngressRoute`; `IngressRouteTCP` with `HostSNI(*)` is required for unencrypted gRPC. Metrics and logs use plain HTTP/1.1 and can share the `web` entrypoint with path-based routing.

**Alternative considered:** Route all three signals over HTTP by wrapping gRPC in HTTP/1.1 (gRPC-Web). Rejected because it requires Alloy exporter changes and adds unnecessary complexity.

---

### D3: Mimir path rewrite via `Middleware replacePath`

**Decision:** Use a Traefik `Middleware` of type `replacePath` to transform `/api/v1/write` → `/api/v1/push` before forwarding to the Mimir distributor.

**Rationale:** Alloy's `prometheus.remote_write` hardcodes `/api/v1/write` as the push path. Mimir's distributor expects `/api/v1/push`. Rewriting at the gateway layer avoids forking the Alloy config and keeps the change transparent.

**Alternative considered:** Configure a custom remote_write path in Alloy. Rejected because it requires modifying shared Alloy config and is non-standard.

---

### D4: `extraPortMappings` in `docker/cluster.yaml`

**Decision:** Add host ports 80 and 4317 mapped to kind container ports 30080 and 30317 in the cluster spec.

**Rationale:** kind only applies `extraPortMappings` at cluster creation time. This is the only supported way to bind host ports to NodePorts inside a kind container. This means the cluster must be recreated when this config first lands.

**Alternative considered:** Use `kubectl port-forward`. Rejected because it requires a persistent foreground process and breaks on pod restarts.

## Risks / Trade-offs

- **Cluster recreation required** → Any data in PVCs (Mimir/Loki/Tempo) will be lost on `make devbox-stop`. Acceptable in a dev environment; documented in the migration plan.
- **Port 80 is a privileged port on Linux** → Binding host port 80 inside kind (which runs as a Docker container) bypasses the OS restriction. Verified to work on WSL2; native Linux may require `CAP_NET_BIND_SERVICE` on Docker. If blocked, users can use port 8080 → 30080 and update `ALLOY_REMOTE_HOST` port accordingly.
- **Single control-plane pod** → If the Traefik pod crashes, all telemetry drops until K8s restarts it. Acceptable for dev; the DaemonSet restart policy handles this automatically.
- **`websecure` entrypoint disabled** → Dashboard and HTTPS are not available. This is intentional for a dev-only setup.

## Migration Plan

1. Run `helm dependency update charts/` to fetch the Traefik chart.
2. Recreate the kind cluster: `make devbox-stop && make devbox-start`.
3. Deploy the updated Helm release: `helm upgrade --install metric-dashboard charts/ -n monitoring`.
4. Verify Traefik pod is on the control-plane node: `kubectl get pods -n monitoring -l app.kubernetes.io/name=traefik -o wide`.
5. Verify NodePort bindings: `kubectl get svc -n monitoring metric-dashboard-traefik`.
6. Copy `backend/.env.example` → `backend/.env` and confirm `ALLOY_REMOTE_HOST=127.0.0.1`.
7. Start Docker Compose: `make dev-start`.
8. Smoke-test each signal (see plan.md verification commands).

**Rollback:** Revert `charts/Chart.yaml`, `charts/values.yaml`, and delete the three new templates; recreate the cluster with the original `docker/cluster.yaml`; restore the previous `backend/.env`.

## Open Questions

- Should `websecure` remain fully disabled or should a commented-out stanza be left for future TLS opt-in?
- If host port 80 is unavailable on a developer's machine, what fallback port should be documented?
