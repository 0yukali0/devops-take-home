## Why

Ticket 3's Site Detail drill-down requires per-container resource metrics (CPU, memory, running state, restarts), but the current Alloy configuration has no container-level scraping — only DB exporters. Without this data, the Grafana Site Detail dashboard cannot be built.

## What Changes

- Add `prometheus.exporter.docker` and a matching `prometheus.scrape` block to Alloy's `config.alloy`, reusing the existing Docker socket mount and `prometheus.relabel.add_labels` pipeline so `DOMAIN`/`STAGE` labels are automatically injected.
- Create a provisioned Grafana dashboard ("Site Detail") with two template variables (`$DOMAIN`, `$STAGE`) that filter all panels, showing container running state, CPU usage, memory usage %, restart count, and per-DB connection/memory metrics.

## Capabilities

### New Capabilities

- `container-metrics`: Scrape per-container CPU, memory, running state, and restart metrics from Docker via Alloy and expose them in Mimir with `DOMAIN`/`STAGE` labels.
- `site-detail-dashboard`: Grafana dashboard with `$DOMAIN` and `$STAGE` dropdown variables; panels display container status and resource usage filtered to the selected domain and stage.

### Modified Capabilities

_(none — existing DB exporter specs are unchanged)_

## Impact

- `backend/alloy/config.alloy` — two new River blocks added.
- `backend/docker-compose.yaml` — no new mounts needed (socket already mounted); a restart of the `alloy` service is required after config change.
- Grafana provisioning — a new dashboard JSON file provisioned via the existing Grafana container setup.
- No API or schema changes; no breaking changes.
