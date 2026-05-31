## ADDED Requirements

### Requirement: Site Detail dashboard is provisioned via Helm
A "Site Detail" Grafana dashboard SHALL be provisioned as a Kubernetes ConfigMap in the `monitoring` namespace, labelled `grafana_dashboard: "1"` so the Grafana sidecar auto-loads it. The dashboard SHALL survive Grafana pod restarts without manual re-import.

#### Scenario: Dashboard is visible after helm upgrade
- **WHEN** `helm upgrade` is run with the new ConfigMap template and `sidecar.dashboards.enabled: true`
- **THEN** the "Site Detail" dashboard appears in Grafana within 60 seconds without restarting the Grafana pod

#### Scenario: Dashboard persists after Grafana pod restart
- **WHEN** the Grafana pod is restarted
- **THEN** the "Site Detail" dashboard is still present after the sidecar re-reconciles

### Requirement: DOMAIN and STAGE template variables filter all panels
The dashboard SHALL have two chained template variables:
- `$DOMAIN`: populated from `label_values(container_running, DOMAIN)` — lists all domains currently reporting metrics, one per backend instance (e.g., `company-1`, `company-2`, `company-3` when `make dev-obs-start` is used).
- `$STAGE`: populated from `label_values(container_running{DOMAIN="$DOMAIN"}, STAGE)` — only stages that exist for the selected domain.

All panel queries SHALL include `{DOMAIN="$DOMAIN", STAGE="$STAGE"}` as label selectors.

#### Scenario: DOMAIN dropdown shows all running instances
- **WHEN** three backend stacks are running via `make dev-obs-start`
- **THEN** the `$DOMAIN` dropdown lists at least `company-1`, `company-2`, and `company-3`

#### Scenario: Selecting DOMAIN scopes STAGE options
- **WHEN** the user selects a specific `$DOMAIN` value
- **THEN** the `$STAGE` dropdown only shows stage values that have data for that domain

#### Scenario: Changing variables refreshes all panels
- **WHEN** the user changes either `$DOMAIN` or `$STAGE`
- **THEN** all panels reload and display data filtered to the newly selected combination

### Requirement: Container status panel shows running state per container
The dashboard SHALL include a panel (type: table or stat) displaying `container_running{DOMAIN="$DOMAIN", STAGE="$STAGE"}`. Each row/cell SHALL show the `container_name` label and its running state, with colour thresholds: green for 1 (running), red for 0 (stopped).

#### Scenario: Running containers display as green
- **WHEN** `container_running` equals 1 for a container in the selected domain/stage
- **THEN** the panel renders that container as green

#### Scenario: Stopped containers display as red
- **WHEN** `container_running` equals 0 for a container in the selected domain/stage
- **THEN** the panel renders that container as red

### Requirement: Per-service resource panels show CPU, memory, and restarts
The dashboard SHALL include panels using `container_name` as the series legend:
- **CPU usage (%)**: `rate(container_cpu_usage_seconds_total{DOMAIN="$DOMAIN", STAGE="$STAGE"}[1m]) * 100` — time-series graph.
- **Memory usage (%)**: `container_memory_usage_bytes{DOMAIN="$DOMAIN", STAGE="$STAGE"} / container_memory_limit_bytes{DOMAIN="$DOMAIN", STAGE="$STAGE"} * 100` — time-series graph.
- **Restart count**: `container_restarts_total{DOMAIN="$DOMAIN", STAGE="$STAGE"}` — stat panel.

#### Scenario: CPU panel shows one series per container
- **WHEN** the dashboard loads with valid `$DOMAIN` and `$STAGE`
- **THEN** the CPU panel displays one time-series line per container, with values between 0 and 100

#### Scenario: Memory panel shows percentage relative to configured limit
- **WHEN** a container's `mem_limit` is set in docker-compose
- **THEN** the memory panel shows a percentage value between 0 and 100 (proportion of the limit used)

#### Scenario: Restart count shows cumulative restarts per container
- **WHEN** a container has restarted N times since last start
- **THEN** the restart stat panel shows N for that container

### Requirement: DB health panels display connection and memory metrics
The dashboard SHALL include DB health panels sourced from the existing DB exporters, filtered by `$DOMAIN` and `$STAGE`:
- **MongoDB current connections**: `mongodb_connections{DOMAIN="$DOMAIN", STAGE="$STAGE", state="current"}`
- **Postgres active connections**: `pg_stat_activity_count{DOMAIN="$DOMAIN", STAGE="$STAGE"}`
- **Redis memory used**: `redis_memory_used_bytes{DOMAIN="$DOMAIN", STAGE="$STAGE"}`

#### Scenario: DB panels show data when DB exporters are active
- **WHEN** Alloy's DB exporters have completed at least one scrape for the selected domain/stage
- **THEN** all three DB panels display non-null values

#### Scenario: DB panels isolate data to selected instance
- **WHEN** the user switches `$DOMAIN` from `company-1` to `company-2`
- **THEN** all DB panels reload and display metrics only for `company-2`
