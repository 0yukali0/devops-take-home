## ADDED Requirements

### Requirement: Traefik is deployed inside the monitoring namespace as a DaemonSet on the control-plane node
Traefik SHALL be installed via Helm as a `DaemonSet` in the `monitoring` namespace, with a `nodeSelector` of `node-role.kubernetes.io/control-plane: ""` and a toleration for the `node-role.kubernetes.io/control-plane:NoSchedule` taint, ensuring it is scheduled on the kind control-plane node.

#### Scenario: Traefik pod lands on control-plane node
- **WHEN** the Helm release is deployed
- **THEN** `kubectl get pods -n monitoring -l app.kubernetes.io/name=traefik -o wide` SHALL show the Traefik pod running on the node with role `control-plane`

---

### Requirement: kind cluster exposes host ports 30080 and 4317 via NodePort
The kind cluster definition (`docker/cluster.yaml`) SHALL declare `extraPortMappings` mapping host port 30080 to container port 30080 (TCP) and host port 4317 to container port 30317 (TCP) on the control-plane node.

#### Scenario: Host port 30080 reaches Traefik HTTP entrypoint
- **WHEN** an HTTP request is sent to `http://127.0.0.1:30080/` from the Docker Compose host
- **THEN** the request SHALL reach the Traefik `web` entrypoint running inside the kind cluster

#### Scenario: Host port 4317 reaches Traefik TCP entrypoint
- **WHEN** a gRPC connection is established to `127.0.0.1:4317` from the Docker Compose host
- **THEN** the connection SHALL reach the Traefik `tempo-grpc` TCP entrypoint inside the kind cluster

---

### Requirement: Traefik exposes two entrypoints — `web` on port 80 and `tempo-grpc` on port 4317
Traefik SHALL be configured with:
- An entrypoint named `web` on port 80, exposed via NodePort 30080.
- An entrypoint named `tempo-grpc` on port 4317, exposed via NodePort 30317, using TCP protocol.

The `websecure` entrypoint SHALL NOT be exposed in the dev environment.

#### Scenario: web entrypoint NodePort is correct
- **WHEN** `kubectl get svc -n monitoring metric-dashboard-traefik` is run
- **THEN** port 80 SHALL map to NodePort 30080

#### Scenario: tempo-grpc entrypoint NodePort is correct
- **WHEN** `kubectl get svc -n monitoring metric-dashboard-traefik` is run
- **THEN** port 4317 SHALL map to NodePort 30317

---

### Requirement: Metrics path `/api/v1/write` is routed to the Mimir distributor with path rewrite
An `IngressRoute` in the `monitoring` namespace SHALL match `PathPrefix("/api/v1/write")` on the `web` entrypoint and, after applying a `Middleware` that replaces the path with `/api/v1/push`, forward the request to the `metric-dashboard-mimir-distributed-distributor` service on port 8080.

#### Scenario: Alloy metrics push reaches Mimir
- **WHEN** a POST request is sent to `http://127.0.0.1:30080/api/v1/write` with a valid Prometheus remote-write payload
- **THEN** the request SHALL be forwarded to the Mimir distributor at `/api/v1/push` and Mimir SHALL respond with HTTP 204

---

### Requirement: Logs path `/loki/api/v1/push` is routed to Loki
An `IngressRoute` in the `monitoring` namespace SHALL match `PathPrefix("/loki/api/v1/push")` on the `web` entrypoint and forward the request unchanged to the `metric-dashboard-loki` service on port 3100.

#### Scenario: Alloy logs push reaches Loki
- **WHEN** a POST request is sent to `http://127.0.0.1:30080/loki/api/v1/push` with a valid Loki push payload
- **THEN** the request SHALL be forwarded to Loki and Loki SHALL respond with HTTP 204

---

### Requirement: gRPC traces are TCP-passthrough routed to Tempo on port 4317
An `IngressRouteTCP` in the `monitoring` namespace SHALL match `HostSNI("*")` on the `tempo-grpc` entrypoint and forward the raw TCP stream to the `metric-dashboard-tempo` service on port 4317.

#### Scenario: Alloy OTLP gRPC traces reach Tempo
- **WHEN** Alloy sends OTLP traces over gRPC to `host.docker.internal:4317`
- **THEN** traces SHALL appear in Grafana's Tempo datasource within the retention window

---

### Requirement: Mimir path rewrite Middleware is defined in the monitoring namespace
A Traefik `Middleware` resource named `mimir-rewrite` SHALL exist in the `monitoring` namespace with `spec.replacePath.path: /api/v1/push`, and SHALL be referenced by the metrics `IngressRoute`.

#### Scenario: Path is rewritten before reaching Mimir
- **WHEN** a request arrives at Traefik matching `/api/v1/write`
- **THEN** Traefik SHALL forward the request to Mimir with the path rewritten to `/api/v1/push`

---

### Requirement: Alloy remote host is configured via a single environment variable
`backend/.env.example` SHALL document `ALLOY_REMOTE_HOST=host.docker.internal`. Alloy's Docker Compose configuration SHALL use this variable for all three telemetry push destinations (metrics, logs, traces), without hardcoded per-service ports.

> **Note:** `host.docker.internal` resolves to the Docker host gateway (`172.17.0.1`) from within the Alloy container on a bridge network. `127.0.0.1` is the container's own loopback and cannot reach the host's NodePorts.

#### Scenario: Alloy config uses ALLOY_REMOTE_HOST
- **WHEN** `ALLOY_REMOTE_HOST=host.docker.internal` is set in `backend/.env`
- **THEN** Alloy SHALL send metrics to `http://host.docker.internal:30080/api/v1/write`, logs to `http://host.docker.internal:30080/loki/api/v1/push`, and traces to `host.docker.internal:4317` (gRPC)
