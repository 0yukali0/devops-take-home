## MODIFIED Requirements

### Requirement: Tempo OTLP ports are exposed via NodePort
The NodePort Service for OTLP SHALL now target Alloy (not Tempo directly), mapping gRPC port 4317 to NodePort 30317 and HTTP port 4318 to NodePort 30318 on Alloy's pods.

#### Scenario: OTLP gRPC on NodePort 30317 routes through Alloy
- **WHEN** an application on the host sends OTLP/gRPC traces to `localhost:30317`
- **THEN** the traffic SHALL be received by Alloy (not Tempo directly), and Alloy SHALL forward the enriched trace to Tempo

#### Scenario: OTLP HTTP on NodePort 30318 routes through Alloy
- **WHEN** an application on the host sends OTLP/HTTP traces to `localhost:30318`
- **THEN** the traffic SHALL be received by Alloy (not Tempo directly), and Alloy SHALL forward the enriched trace to Tempo

## ADDED Requirements

### Requirement: Tempo OTLP receiver accepts connections from Alloy in-cluster
`charts/values.yaml` SHALL configure Tempo's OTLP gRPC receiver to accept connections on port 4317, reachable by Alloy within the cluster namespace.

#### Scenario: Alloy can reach Tempo OTLP gRPC endpoint in-cluster
- **WHEN** Alloy forwards a trace to Tempo's cluster-internal gRPC endpoint on port 4317
- **THEN** Tempo SHALL accept and store the spans without error
