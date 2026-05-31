## ADDED Requirements

### Requirement: Chart declares mimir-distributed dependency from Grafana Helm repository
`charts/Chart.yaml` SHALL declare `mimir-distributed` as a dependency from `https://grafana.github.io/helm-charts` with a pinned version.

#### Scenario: Chart.yaml contains mimir-distributed dependency
- **WHEN** a developer inspects `charts/Chart.yaml`
- **THEN** it SHALL contain a `dependencies` entry with `name: mimir-distributed` and `repository: https://grafana.github.io/helm-charts`

### Requirement: Prometheus is disabled in kube-prometheus-stack
`charts/values.yaml` SHALL set `kube-prometheus-stack.prometheus.enabled: false` so that no Prometheus server pod is deployed.

#### Scenario: No Prometheus server pod runs after deployment
- **WHEN** the chart is deployed
- **THEN** no pod matching the Prometheus server label SHALL be running in the monitoring namespace

### Requirement: Mimir runs in single-replica mode with local filesystem storage
`charts/values.yaml` SHALL configure mimir-distributed with all component replicas set to 1, `minio.enabled: false`, and local filesystem storage to match devbox constraints.

#### Scenario: Mimir components start with a single replica each
- **WHEN** the chart is deployed
- **THEN** each Mimir component (distributor, ingester, querier, query-frontend, compactor, store-gateway) SHALL have exactly one replica running

### Requirement: Mimir data retention is set to 24 hours
`charts/values.yaml` SHALL configure Mimir's compactor with a `blocks-retention-period` of `24h`.

#### Scenario: Mimir enforces 24h retention
- **WHEN** metric blocks older than 24h exist in Mimir's store
- **THEN** Mimir's compactor SHALL delete those blocks on its next compaction cycle

### Requirement: Mimir is wired as the primary metrics datasource in Grafana
`charts/values.yaml` SHALL replace the default Prometheus datasource with a `prometheus`-type datasource pointing to Mimir's query-frontend in-cluster HTTP endpoint (`/prometheus` prefix) on port 8080.

#### Scenario: Grafana Mimir datasource is available and queryable
- **WHEN** a user opens Grafana and navigates to datasources
- **THEN** a datasource named `Mimir` of type `prometheus` SHALL be present and return results for a PromQL query

### Requirement: Mimir uses ephemeral (non-persistent) storage
`charts/values.yaml` SHALL configure Mimir with no PersistentVolumeClaims for the devbox environment.

#### Scenario: Mimir does not create PersistentVolumeClaims
- **WHEN** the chart is deployed
- **THEN** no PersistentVolumeClaim associated with Mimir SHALL be created
