## Context

The current observability umbrella chart (`charts/`) bundles kube-prometheus-stack (Prometheus + Grafana + AlertManager), Tempo (traces), and Alloy (OTLP collector pipeline). Prometheus stores metrics locally with no scalable backend. There is no log aggregation. Alloy forwards OTLP traces via NodePort 30317/30318 to Tempo, adding an extra hop and requiring an explicit NodePort Service template.

The target state: Loki (logs) + Mimir (metrics storage, replacing Prometheus) + Tempo (traces) under a single Helm umbrella, all with 24h retention, with Alloy removed and Grafana pre-wired to all three backends.

## Goals / Non-Goals

**Goals:**
- Add Loki in single-binary mode for log collection and querying
- Add Mimir (mimir-distributed) as the sole metrics backend, replacing Prometheus
- Disable Prometheus server in kube-prometheus-stack (retain Grafana + AlertManager)
- Set 24h data retention on Loki and Mimir (Tempo already has 24h)
- Wire Loki and Mimir as Grafana datasources; remove the now-unused Prometheus datasource
- Remove Alloy subchart and its NodePort Service

**Non-Goals:**
- Enabling persistent storage for Loki or Mimir (keeping ephemeral storage for devbox)
- Log shipping configuration (Promtail / k8s event router) — out of scope for this chart update
- Production-grade Mimir sizing or object storage backend — devbox uses local filesystem
- Changing Tempo configuration

## Decisions

### D1: Loki single-binary vs. microservices
Use `single-binary` deployment mode (one pod, all Loki components). The microservices mode requires separate deployments per component and is not appropriate for a devbox environment.

### D2: Mimir deployment mode
Use `mimir-distributed` chart configured as a monolithic single-replica setup (`minio.enabled: false`, all components at `replicas: 1`, local filesystem storage). The mimir-distributed chart is the canonical Grafana Helm chart.

### D3: Mimir replaces Prometheus
Disable `prometheus.enabled: false` in kube-prometheus-stack. Mimir serves as the complete metrics backend — it includes its own scraper (ruler + compactor). Grafana's datasource points to Mimir's querier endpoint instead of a Prometheus server.

**Alternative considered**: Keep Prometheus as a scraper and remote-write to Mimir. Rejected — running both Prometheus and Mimir is redundant for a devbox environment; Mimir can handle metric ingestion directly.

### D4: Alloy removal
Delete the `alloy` dependency from `Chart.yaml` and its values block. Delete `charts/templates/alloy-otlp-nodeport.yaml`. OTLP traffic that previously hit NodePort 30317/30318 must target Tempo's in-cluster gRPC endpoint directly. This is a breaking change, documented in the proposal.

### D5: Grafana datasource wiring
Replace the existing Prometheus datasource with Mimir, and add Loki:
- **Mimir** (replaces Prometheus) — type `prometheus`, URL `http://<release>-mimir-distributed-query-frontend.<namespace>.svc.cluster.local:8080/prometheus`
- **Loki** — type `loki`, URL `http://<release>-loki.<namespace>.svc.cluster.local:3100`
- **Tempo** — unchanged

## Risks / Trade-offs

- [Prometheus disabled — no scraping by default] Mimir needs its own scrape config or ServiceMonitor integration → Mitigation: configure Mimir's built-in scraper or wire kube-prometheus-stack's prometheus-operator CRDs to Mimir; document this in the chart
- [Mimir single-replica instability] In-memory ring state can stall on pod restart → Mitigation: devbox only; use `memberlist.join_members` pointing to self
- [Alloy NodePort removal breaks callers] Services sending traces to 30317/30318 will fail → Mitigation: document new direct-to-Tempo endpoint; breaking change flagged in proposal
- [Loki has no log shipper] Loki is available but receives no logs until Promtail or similar is added → Acceptable; Loki is ready when an agent is added later
- [Chart dependency version drift] Pinning Loki and Mimir chart versions may drift → Mitigation: pin explicit versions in `Chart.yaml`

## Migration Plan

1. `helm dependency update charts/` — pulls new Loki and Mimir chart tarballs, drops Alloy
2. `helm upgrade <release> charts/ -n <namespace>` — deploys Loki and Mimir, removes Alloy pods and NodePort Service, stops Prometheus server
3. Verify Grafana datasources load (Loki, Mimir, Tempo)
4. Update any services pointing to NodePort 30317/30318 to use the Tempo in-cluster address

**Rollback**: `helm rollback <release>` restores previous chart revision including Alloy and Prometheus.

## Open Questions

- Which Loki chart version to pin? (Use latest stable from `https://grafana.github.io/helm-charts`)
- Should kube-prometheus-stack's prometheus-operator remain enabled to manage ServiceMonitor CRDs for Mimir scraping, or should it also be disabled?
