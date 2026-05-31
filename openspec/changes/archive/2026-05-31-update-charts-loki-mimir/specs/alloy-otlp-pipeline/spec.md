## REMOVED Requirements

### Requirement: Chart declares Alloy dependency from grafana Helm repository
**Reason**: Alloy is removed from the observability stack; OTLP trace ingestion now goes directly to Tempo without a collector sidecar.
**Migration**: Remove the `alloy` dependency entry from `charts/Chart.yaml`. Services that sent traces to Alloy's NodePort (30317 gRPC, 30318 HTTP) MUST update their OTLP endpoint to `<release>-tempo.<namespace>.svc.cluster.local:4317` (gRPC) or `:4318` (HTTP).

### Requirement: Alloy is deployed with an OTLP receiver on gRPC 4317 and HTTP 4318
**Reason**: Alloy is removed; no collector pod is deployed.
**Migration**: Send OTLP traces directly to Tempo's in-cluster endpoints.

### Requirement: Alloy attaches a cluster resource attribute to all traces
**Reason**: Alloy is removed; cluster attribute enrichment is no longer applied at the collector layer.
**Migration**: Instrument services to include the `cluster` resource attribute at the SDK level if the attribute is required.

### Requirement: Alloy forwards enriched traces to Tempo via OTLP/gRPC
**Reason**: Alloy is removed; traces are sent directly to Tempo.
**Migration**: Configure OTLP exporters to target Tempo directly.

### Requirement: Alloy OTLP NodePort is exposed on ports 30317 and 30318
**Reason**: Alloy is removed; `charts/templates/alloy-otlp-nodeport.yaml` is deleted.
**Migration**: Use Tempo's NodePort or in-cluster service. If a NodePort is needed for Tempo, add a separate NodePort Service targeting Tempo's ports 4317/4318.
