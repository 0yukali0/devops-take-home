## ADDED Requirements

### Requirement: Grafana has Tempo provisioned as a datasource
`charts/values.yaml` SHALL configure `kube-prometheus-stack.grafana.additionalDataSources` with a Tempo datasource entry so that traces are queryable in Grafana immediately after deployment.

#### Scenario: Tempo datasource visible in Grafana
- **WHEN** a user opens Grafana and navigates to Configuration → Data Sources
- **THEN** a datasource of type `tempo` SHALL be listed with a reachable URL pointing to the Tempo service in the monitoring namespace

### Requirement: Tempo datasource URL points to the in-cluster Tempo service
The Tempo datasource URL in `charts/values.yaml` SHALL use the in-cluster DNS name `http://metric-dashboard-tempo.monitoring.svc.cluster.local:3200`.

#### Scenario: Datasource URL resolves correctly
- **WHEN** Grafana performs a datasource health check against the configured Tempo URL
- **THEN** the check SHALL succeed (HTTP 200) confirming Grafana can reach Tempo

### Requirement: Tempo datasource is selectable in Grafana Explore
The Tempo datasource SHALL be available in Grafana Explore so users can query traces by selecting it from the datasource picker. It is NOT set as isDefault because Grafana enforces a single global default and the Prometheus datasource already holds that role.

#### Scenario: Tempo visible in Explore datasource picker
- **WHEN** a user opens Grafana Explore
- **THEN** the Tempo datasource SHALL appear in the datasource picker and be selectable for trace queries
