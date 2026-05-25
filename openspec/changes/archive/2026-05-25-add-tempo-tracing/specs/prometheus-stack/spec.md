## ADDED Requirements

### Requirement: values.yaml contains a tempo section
`charts/values.yaml` SHALL contain a top-level `tempo:` key with subchart configuration values (storage, retention, receivers, Grafana disabled, NodePort service).

#### Scenario: tempo key present in values
- **WHEN** a developer inspects `charts/values.yaml`
- **THEN** it SHALL contain a `tempo:` top-level key with at minimum the emptyDir storage, 24h retention, OTLP receivers, `grafana.enabled: false`, and NodePort service configuration

### Requirement: kube-prometheus-stack Grafana has additionalDataSources configured
`charts/values.yaml` SHALL configure `kube-prometheus-stack.grafana.additionalDataSources` with an entry for Tempo so that the provisioning is applied when the chart is deployed.

#### Scenario: additionalDataSources contains Tempo
- **WHEN** a developer inspects `charts/values.yaml`
- **THEN** `kube-prometheus-stack.grafana.additionalDataSources` SHALL contain at least one entry with `type: tempo`
