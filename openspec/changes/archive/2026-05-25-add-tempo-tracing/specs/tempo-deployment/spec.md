## ADDED Requirements

### Requirement: Chart declares Tempo dependency from grafana-community
`charts/Chart.yaml` SHALL declare `tempo` as a dependency with repository `https://grafana-community.github.io/helm-charts`.

#### Scenario: Chart.yaml contains Tempo dependency
- **WHEN** a developer inspects `charts/Chart.yaml`
- **THEN** it SHALL contain a `dependencies` entry with `name: tempo` and `repository: https://grafana-community.github.io/helm-charts`

### Requirement: Tempo uses emptyDir storage
`charts/values.yaml` SHALL configure Tempo to use emptyDir storage so that no PersistentVolumeClaim is required.

#### Scenario: Tempo starts without a PVC
- **WHEN** the chart is deployed to a cluster without a default StorageClass
- **THEN** the Tempo pod SHALL start successfully using emptyDir storage (no PVC pending state)

### Requirement: Tempo retains traces for 1 day
`charts/values.yaml` SHALL configure Tempo with a trace retention period of 24 hours.

#### Scenario: Retention is set to 24h
- **WHEN** a developer inspects the effective Tempo configuration
- **THEN** the retention field SHALL be set to `24h`

### Requirement: Tempo has OTLP receivers enabled
`charts/values.yaml` SHALL configure Tempo to accept traces over OTLP gRPC (port 4317) and OTLP HTTP (port 4318).

#### Scenario: OTLP gRPC receiver is enabled
- **WHEN** a trace-producing application sends spans to the Tempo pod on port 4317 using the OTLP/gRPC protocol
- **THEN** Tempo SHALL accept and store the spans without error

#### Scenario: OTLP HTTP receiver is enabled
- **WHEN** a trace-producing application sends spans to the Tempo pod on port 4318 using the OTLP/HTTP protocol
- **THEN** Tempo SHALL accept and store the spans without error

### Requirement: Tempo chart's own Grafana instance is disabled
`charts/values.yaml` SHALL set `tempo.grafana.enabled: false` to prevent the Tempo chart from deploying a second Grafana instance.

#### Scenario: No duplicate Grafana deployed
- **WHEN** the umbrella chart is deployed
- **THEN** only one Grafana Deployment SHALL exist in the monitoring namespace (the one from kube-prometheus-stack)

### Requirement: Tempo OTLP ports are exposed via NodePort
`charts/values.yaml` SHALL configure a NodePort Service for Tempo that maps gRPC port 4317 to NodePort 30317 and HTTP port 4318 to NodePort 30318.

#### Scenario: OTLP gRPC reachable on NodePort
- **WHEN** an application on the host sends OTLP/gRPC traces to `localhost:30317`
- **THEN** Tempo SHALL receive and store those spans

#### Scenario: OTLP HTTP reachable on NodePort
- **WHEN** an application on the host sends OTLP/HTTP traces to `localhost:30318`
- **THEN** Tempo SHALL receive and store those spans
