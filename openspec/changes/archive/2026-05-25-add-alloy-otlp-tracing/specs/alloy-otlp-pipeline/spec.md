## ADDED Requirements

### Requirement: Chart declares Alloy dependency from grafana Helm repository
`charts/Chart.yaml` SHALL declare `alloy` as a dependency from `https://grafana.github.io/helm-charts`.

#### Scenario: Chart.yaml contains Alloy dependency
- **WHEN** a developer inspects `charts/Chart.yaml`
- **THEN** it SHALL contain a `dependencies` entry with `name: alloy` and `repository: https://grafana.github.io/helm-charts`

### Requirement: Alloy is deployed with an OTLP receiver on gRPC 4317 and HTTP 4318
`charts/values.yaml` SHALL configure Alloy with an `otelcol.receiver.otlp` component that listens on gRPC port 4317 and HTTP port 4318.

#### Scenario: Alloy accepts OTLP/gRPC traces on port 4317
- **WHEN** a backend sends spans to Alloy's gRPC endpoint on port 4317
- **THEN** Alloy SHALL accept the spans without error

#### Scenario: Alloy accepts OTLP/HTTP traces on port 4318
- **WHEN** a backend sends spans to Alloy's HTTP endpoint on port 4318
- **THEN** Alloy SHALL accept the spans without error

### Requirement: Alloy attaches a cluster resource attribute to all traces
`charts/values.yaml` SHALL configure Alloy with an `otelcol.processor.attributes` component that inserts a `cluster` resource attribute on every trace span, with the value sourced from the `alloy.clusterName` Helm value.

#### Scenario: Trace spans contain cluster attribute after pipeline
- **WHEN** a span passes through Alloy
- **THEN** it SHALL have a resource attribute `cluster` equal to the value provided via `--set alloy.clusterName=<value>`

#### Scenario: Default cluster name is used when not set
- **WHEN** the chart is deployed without setting `alloy.clusterName`
- **THEN** spans forwarded to Tempo SHALL have a resource attribute `cluster` equal to `"default"`

### Requirement: Alloy forwards enriched traces to Tempo via OTLP/gRPC
`charts/values.yaml` SHALL configure Alloy with an `otelcol.exporter.otlp` component that sends traces to Tempo's in-cluster gRPC endpoint on port 4317.

#### Scenario: Traces appear in Tempo after Alloy pipeline
- **WHEN** a backend sends a trace to Alloy's OTLP receiver
- **THEN** the trace SHALL be visible in Tempo (queryable via Grafana) with the `cluster` attribute attached

### Requirement: Alloy OTLP NodePort is exposed on ports 30317 and 30318
The chart SHALL expose Alloy's OTLP receiver on NodePort 30317 (gRPC) and NodePort 30318 (HTTP) so that host-side backends can reach it without reconfiguration.

#### Scenario: Alloy OTLP gRPC reachable on NodePort 30317
- **WHEN** an application on the host sends OTLP/gRPC traces to `localhost:30317`
- **THEN** Alloy SHALL receive the spans and forward them to Tempo

#### Scenario: Alloy OTLP HTTP reachable on NodePort 30318
- **WHEN** an application on the host sends OTLP/HTTP traces to `localhost:30318`
- **THEN** Alloy SHALL receive the spans and forward them to Tempo
