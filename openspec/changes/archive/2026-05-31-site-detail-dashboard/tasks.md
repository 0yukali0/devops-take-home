## 1. Alloy — Add Container Metrics Scraping

- [x] 1.1 Add `prometheus.exporter.docker "containers"` block to `backend/alloy/config.alloy` pointing to `unix:///var/run/docker.sock`
- [x] 1.2 Add `prometheus.scrape "docker"` block that forwards to `prometheus.relabel.add_labels.receiver` with `job_name = "docker"`
- [x] 1.3 Restart Alloy (`docker compose restart alloy` for each running instance) and verify `container_running` metrics appear in Grafana Explore under the Mimir datasource

## 2. Helm Chart — Enable Grafana Dashboard Sidecar

- [x] 2.1 Add `grafana.sidecar.dashboards.enabled: true` under `kube-prometheus-stack` in `charts/values.yaml`

## 3. Grafana Dashboard — Site Detail ConfigMap

- [x] 3.1 Create `charts/templates/grafana-dashboard-site-detail.yaml` as a ConfigMap in `namespace: monitoring` with label `grafana_dashboard: "1"`
- [x] 3.2 Add `$DOMAIN` template variable using `label_values(container_running, DOMAIN)` sourced from the Mimir datasource
- [x] 3.3 Add `$STAGE` template variable using `label_values(container_running{DOMAIN="$DOMAIN"}, STAGE)` chained on `$DOMAIN`
- [x] 3.4 Add "Container Status" panel (Stat or Table type) with query `container_running{DOMAIN="$DOMAIN", STAGE="$STAGE"}`, legend `{{container_name}}`, thresholds green=1 / red=0
- [x] 3.5 Add "CPU Usage (%)" time-series panel with query `rate(container_cpu_usage_seconds_total{DOMAIN="$DOMAIN", STAGE="$STAGE"}[1m]) * 100`, legend `{{container_name}}`
- [x] 3.6 Add "Memory Usage (%)" time-series panel with query `container_memory_usage_bytes{DOMAIN="$DOMAIN", STAGE="$STAGE"} / container_memory_limit_bytes{DOMAIN="$DOMAIN", STAGE="$STAGE"} * 100`, legend `{{container_name}}`
- [x] 3.7 Add "Container Restarts" stat panel with query `container_restarts_total{DOMAIN="$DOMAIN", STAGE="$STAGE"}`, legend `{{container_name}}`
- [x] 3.8 Add "MongoDB Connections" stat panel with query `mongodb_connections{DOMAIN="$DOMAIN", STAGE="$STAGE", state="current"}`
- [x] 3.9 Add "Postgres Active Connections" stat panel with query `pg_stat_activity_count{DOMAIN="$DOMAIN", STAGE="$STAGE"}`
- [x] 3.10 Add "Redis Memory Used" stat panel with query `redis_memory_used_bytes{DOMAIN="$DOMAIN", STAGE="$STAGE"}`

## 4. Deploy and Verify

- [x] 4.1 Run `helm upgrade` on the monitoring chart and confirm the `grafana-dashboard-site-detail` ConfigMap exists in the `monitoring` namespace
- [x] 4.2 Confirm the "Site Detail" dashboard appears in Grafana within 60 seconds without restarting the Grafana pod
- [x] 4.3 Run `make dev-obs-start` and verify `$DOMAIN` dropdown lists `company-1`, `company-2`, `company-3`
- [x] 4.4 Select each domain and verify all panels load data for that instance only
- [x] 4.5 Verify container status panel shows green for running containers and red for any stopped ones
