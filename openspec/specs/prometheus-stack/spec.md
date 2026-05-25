# Spec: prometheus-stack

## Requirements

### Requirement: Chart dependency declares kube-prometheus-stack via OCI
`charts/Chart.yaml` SHALL declare `kube-prometheus-stack` as a dependency using the OCI source `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`.

#### Scenario: Chart.yaml contains the OCI dependency
- **WHEN** a developer inspects `charts/Chart.yaml`
- **THEN** it SHALL contain a `dependencies` entry with `name: kube-prometheus-stack` and `repository: oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`

### Requirement: values.yaml enables all four monitoring components
`charts/values.yaml` SHALL explicitly enable Prometheus Operator, Prometheus, Grafana, and AlertManager by setting their respective `enabled` flags to `true` under the `kube-prometheus-stack` key.

#### Scenario: All components enabled in values
- **WHEN** a developer inspects `charts/values.yaml`
- **THEN** it SHALL contain `prometheusOperator.enabled: true`, `prometheus.enabled: true`, `grafana.enabled: true`, and `alertmanager.enabled: true` under the `kube-prometheus-stack` section

### Requirement: Prometheus and Grafana use emptyDir storage
`charts/values.yaml` SHALL configure Prometheus and Grafana to use `emptyDir` storage so that no PersistentVolumeClaim is required.

#### Scenario: Prometheus storage set to emptyDir
- **WHEN** the chart is deployed to a cluster without a default StorageClass
- **THEN** Prometheus pods SHALL start successfully using emptyDir volumes (no PVC pending state)

#### Scenario: Grafana storage set to emptyDir
- **WHEN** the chart is deployed to a cluster without a default StorageClass
- **THEN** Grafana pods SHALL start successfully using emptyDir volumes (no PVC pending state)

### Requirement: charts/Makefile provides obs-deploy target
`charts/Makefile` SHALL define an `obs-deploy` target that resolves Helm dependencies and installs or upgrades the release `metric-dashboard` in the `monitoring` namespace.

#### Scenario: obs-deploy runs helm dependency build when lock file exists
- **WHEN** `charts/Chart.lock` exists and `make obs-deploy` is run
- **THEN** it SHALL execute `helm dependency build` before installing

#### Scenario: obs-deploy runs helm dependency update when no lock file
- **WHEN** `charts/Chart.lock` does not exist and `make obs-deploy` is run
- **THEN** it SHALL execute `helm dependency update` to resolve and lock dependencies

#### Scenario: obs-deploy installs the release idempotently
- **WHEN** `make obs-deploy` is run against a cluster (first time or subsequent)
- **THEN** it SHALL execute `helm upgrade --install metric-dashboard . -n monitoring --create-namespace` and complete without error

### Requirement: devbox-start deploys the monitoring stack end-to-end
Running `make devbox-start` from the project root SHALL start the kind cluster and deploy the monitoring stack via `obs-deploy`.

#### Scenario: Full devbox-start succeeds
- **WHEN** `make devbox-start` is run from the project root
- **THEN** the kind cluster SHALL be created and the `metric-dashboard` Helm release SHALL be present in the `monitoring` namespace

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
