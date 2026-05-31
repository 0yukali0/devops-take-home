## ADDED Requirements

### Requirement: Alloy scrapes container-level metrics via Docker socket
Alloy SHALL use `prometheus.exporter.docker` to scrape per-container metrics from the Docker Engine API through the already-mounted socket at `unix:///var/run/docker.sock`. The scrape job SHALL forward metrics to the existing `prometheus.relabel.add_labels` receiver so that `DOMAIN` and `STAGE` labels are automatically injected into every metric.

#### Scenario: Metrics available in Mimir after Alloy restart
- **WHEN** Alloy is restarted after the docker exporter blocks are added to `config.alloy`
- **THEN** querying `container_running{DOMAIN="<any-domain>"}` in Grafana Explore returns at least one data point per running container

#### Scenario: DOMAIN and STAGE labels are present on all container metrics
- **WHEN** container metrics are scraped and written to Mimir
- **THEN** every metric series carries both a `DOMAIN` label matching `ALLOY_DOMAIN` and a `STAGE` label matching `ALLOY_STAGE`

#### Scenario: Multiple backend instances each report their own DOMAIN
- **WHEN** `make dev-obs-start` launches three backend stacks (INSTANCE 1, 2, 3)
- **THEN** `label_values(container_running, DOMAIN)` returns a distinct value for each instance (e.g., `company-1`, `company-2`, `company-3`)

### Requirement: Exposed container metrics set
Alloy SHALL expose at minimum the following container metrics in Mimir:

| Metric | Description |
|--------|-------------|
| `container_running` | 1 if the container is running, 0 if stopped |
| `container_cpu_usage_seconds_total` | Cumulative CPU seconds (use `rate()` to derive usage %) |
| `container_memory_usage_bytes` | Current memory usage in bytes |
| `container_memory_limit_bytes` | Configured memory limit in bytes |
| `container_restarts_total` | Cumulative restart count |

#### Scenario: container_running reflects actual container state
- **WHEN** a container is running
- **THEN** `container_running{container_name="<name>"}` equals 1
- **WHEN** a container is stopped or missing
- **THEN** `container_running{container_name="<name>"}` equals 0

#### Scenario: Memory percentage is computable
- **WHEN** a service has `mem_limit` configured in docker-compose
- **THEN** `container_memory_limit_bytes` is non-zero and `container_memory_usage_bytes / container_memory_limit_bytes * 100` yields a valid percentage

#### Scenario: CPU usage rate is computable
- **WHEN** a container has been running for at least one scrape interval
- **THEN** `rate(container_cpu_usage_seconds_total[1m])` returns a non-negative value
