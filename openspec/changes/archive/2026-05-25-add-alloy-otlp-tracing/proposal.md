## Why

The current setup exposes Tempo's OTLP ports directly via NodePort, requiring backend services to ship traces straight to Tempo with no intermediate processing. Adding Grafana Alloy as a collector pipeline enables trace enrichment (e.g., attaching a `cluster` label) before forwarding to Tempo, and provides a single configurable ingestion point that decouples backends from the storage backend.

## What Changes

- Add `alloy` (grafana/alloy Helm chart) as a new dependency in `charts/Chart.yaml`
- Configure Alloy to expose an OTLP receiver (gRPC 4317, HTTP 4318) for incoming traces from backend services
- Configure Alloy to enrich traces with a `cluster` attribute whose value is supplied via `--set alloy.cluster=<value>` at install time
- Configure Alloy to forward enriched traces to Tempo via OTLP/gRPC
- Update Tempo's OTLP receiver to only accept connections from within the cluster (Alloy), no longer needing direct NodePort exposure for trace ingestion
- NodePort services for OTLP are re-pointed to Alloy's receiver ports so existing backends need no reconfiguration

## Capabilities

### New Capabilities

- `alloy-otlp-pipeline`: Grafana Alloy deployed as an OTLP trace collector — receives traces, attaches `cluster` label, and forwards to Tempo

### Modified Capabilities

- `tempo-deployment`: Tempo's OTLP receiver is now intended to receive from Alloy (cluster-internal), not directly from external backends; NodePort exposure moves to Alloy

## Impact

- `charts/Chart.yaml`: adds `alloy` dependency
- `charts/Chart.lock`: updated after `helm dependency update`
- `charts/values.yaml`: adds `alloy` subchart config (River/Alloy config, cluster value, service config); updates `tempo` receiver config if needed
- `charts/templates/`: may add or update NodePort service template to point at Alloy instead of Tempo
- Existing `openspec/specs/tempo-deployment/spec.md`: requirement for NodePort on Tempo OTLP ports needs updating
