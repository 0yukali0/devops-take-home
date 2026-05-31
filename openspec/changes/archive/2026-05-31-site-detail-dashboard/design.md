## Context

The observability stack runs on Kubernetes (kube-prometheus-stack Helm chart). Metrics flow from per-site Docker Compose stacks → Alloy → Mimir. Each Alloy instance stamps every metric with `DOMAIN` and `STAGE` labels via `prometheus.relabel.add_labels`. Grafana is deployed as part of the Helm chart and already has Mimir, Loki, and Tempo configured as data sources.

**Current gaps:**
1. `config.alloy` has no Docker container exporter — only DB exporters. Container-level CPU/memory/state metrics are absent from Mimir.
2. No Site Detail dashboard exists in Grafana.

**Constraints:**
- The Docker socket (`/var/run/docker.sock`) is already mounted read-only in the Alloy container — no docker-compose changes needed.
- `ALLOY_TENANT_ID` is `${ALLOY_DOMAIN}-${ALLOY_STAGE}-${INSTANCE}`. Metrics are namespaced by tenant; all queries must pass the correct org ID header (handled by Mimir datasource).
- Dashboard provisioning must work without persistent storage (Grafana `persistence.enabled: false`).

## Goals / Non-Goals

**Goals:**
- Expose `container_running`, `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, `container_memory_limit_bytes`, `container_restarts_total` in Mimir with `DOMAIN`/`STAGE` labels.
- Provision a "Site Detail" Grafana dashboard with `$DOMAIN` and `$STAGE` template variables; panels filter to the selected combination.
- Include container status (running/stopped), per-service CPU%, memory%, restart count, and DB health panels (MongoDB connections, Postgres connections, Redis memory).

**Non-Goals:**
- Host disk usage — requires node_exporter with host filesystem mounts; out of scope for MVP.
- Per-tenant Mimir auth — Grafana's Mimir datasource is already configured to hit the single-tenant endpoint.
- Dashboard alerting rules.

## Decisions

### D1 — Use `prometheus.exporter.docker` in Alloy (not a standalone cAdvisor)

**Decision:** Add `prometheus.exporter.docker` directly to `config.alloy`.

**Rationale:** Alloy already has the Docker socket mounted and exposes `prometheus.exporter.docker` as a built-in component. Forwarding to the existing `prometheus.relabel.add_labels` receiver means `DOMAIN`/`STAGE` labels are injected automatically with zero extra configuration. Deploying a separate cAdvisor sidecar would add another container, image pull, and port-mapping with no benefit.

**Alternative considered:** `prometheus.exporter.unix` — covers host CPU/memory/disk but not per-container stats; would require privileged mounts. Rejected.

### D2 — Provision dashboard via Helm ConfigMap + Grafana sidecar

**Decision:** Add a `grafana-dashboard-site-detail` ConfigMap template under `charts/templates/` and enable `grafana.sidecar.dashboards` in `values.yaml`.

**Rationale:** Grafana `persistence.enabled: false`, so any dashboard saved in the UI is lost on pod restart. The kube-prometheus-stack chart ships a Grafana sidecar (`grafana-sc-dashboard`) that watches ConfigMaps labelled `grafana_dashboard: "1"` and hot-loads them — no Grafana restart required. This is the standard GitOps-friendly approach for this chart.

**Alternative considered:** `grafana.dashboards` in `values.yaml` (inline JSON) — works but embeds a large JSON blob in values.yaml, making it hard to review diffs. Separate ConfigMap template is cleaner.

### D3 — Two template variables: `$DOMAIN` and `$STAGE`

**Decision:** Dashboard has two chained query variables:
- `$DOMAIN` — `label_values(container_running, DOMAIN)` (values from Mimir)
- `$STAGE` — `label_values(container_running{DOMAIN="$DOMAIN"}, STAGE)` (chained on `$DOMAIN`)

All panel queries filter with `{DOMAIN="$DOMAIN", STAGE="$STAGE"}`.

**Rationale:** Mirrors the actual label structure injected by Alloy. Chaining `$STAGE` on `$DOMAIN` prevents invalid combinations.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| `prometheus.exporter.docker` is not available in the Alloy version pinned in docker-compose | Use `grafana/alloy:latest`; the docker exporter has been stable since Alloy v1.0. If pinning to a specific version, verify with `alloy run --list-components`. |
| `container_memory_limit_bytes` is 0 when no `mem_limit` is set in docker-compose | All services already have `mem_limit` set. Panel query uses division — a zero limit would show NaN, not crash. |
| ConfigMap size limit (1 MiB) | Dashboard JSON is well under 100 KB. |
| Grafana sidecar not watching the right namespace | ConfigMap must be in the `monitoring` namespace (same as Grafana pod). Template adds `namespace: monitoring`. |

## Migration Plan

1. **Alloy config** — Edit `backend/alloy/config.alloy`, add docker exporter + scrape blocks. Restart Alloy via `docker compose restart alloy` per site. Verify with `container_running{DOMAIN="<site>"}` in Grafana Explore.
2. **Helm values** — Enable `grafana.sidecar.dashboards` in `charts/values.yaml`.
3. **Dashboard ConfigMap** — Add `charts/templates/grafana-dashboard-site-detail.yaml` with the dashboard JSON.
4. **Deploy** — `helm upgrade` the chart. Grafana sidecar auto-loads the dashboard within ~30 s.
5. **Rollback** — Remove the ConfigMap template and re-run `helm upgrade`. Sidecar removes the dashboard on next reconcile. Alloy config change can be reverted and `docker compose restart alloy` re-run.

## Open Questions

- Should `$DOMAIN` default to "All" (multi-select) or single-select? Single-select is assumed for a site detail drill-down.
- Are there additional per-service panels desired beyond CPU/memory/restarts (e.g., network I/O)? Network metrics are available but not in the initial scope.
