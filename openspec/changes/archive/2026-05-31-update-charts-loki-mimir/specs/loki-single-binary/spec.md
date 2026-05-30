## ADDED Requirements

### Requirement: Chart declares Loki dependency from Grafana Helm repository
`charts/Chart.yaml` SHALL declare `loki` as a dependency from `https://grafana.github.io/helm-charts` with a pinned version.

#### Scenario: Chart.yaml contains Loki dependency
- **WHEN** a developer inspects `charts/Chart.yaml`
- **THEN** it SHALL contain a `dependencies` entry with `name: loki` and `repository: https://grafana.github.io/helm-charts`

### Requirement: Loki runs in single-binary deployment mode
`charts/values.yaml` SHALL configure Loki with `deploymentMode: SingleBinary` and a single replica.

#### Scenario: Loki pod starts in single-binary mode
- **WHEN** the chart is deployed
- **THEN** exactly one Loki pod SHALL be running with all Loki components collocated in a single process

### Requirement: Loki data retention is set to 24 hours
`charts/values.yaml` SHALL configure Loki with a retention period of 24h.

#### Scenario: Loki enforces 24h retention
- **WHEN** log entries older than 24h exist in Loki's store
- **THEN** Loki SHALL not return those entries in queries

### Requirement: Loki is wired as a Grafana datasource
`charts/values.yaml` SHALL add a Loki datasource to `kube-prometheus-stack.grafana.additionalDataSources` pointing to Loki's in-cluster HTTP endpoint on port 3100.

#### Scenario: Grafana Loki datasource is available
- **WHEN** a user opens Grafana and navigates to datasources
- **THEN** a datasource named `Loki` of type `loki` SHALL be present and reachable

### Requirement: Loki uses ephemeral (non-persistent) storage
`charts/values.yaml` SHALL configure Loki with `persistence.enabled: false` for the devbox environment.

#### Scenario: Loki does not create a PersistentVolumeClaim
- **WHEN** the chart is deployed
- **THEN** no PersistentVolumeClaim associated with Loki SHALL be created
