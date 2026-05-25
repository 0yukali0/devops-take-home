## Why

The current `charts/` Helm chart is an empty scaffold with no observability components defined. The `devbox-start` target already invokes `obs-deploy` from the charts directory, but nothing is actually deployed — there is no monitoring, alerting, or metrics stack in place for the Kubernetes devbox environment.

## What Changes

- Replace the current empty `charts/` scaffold with a proper Helm umbrella chart that declares `kube-prometheus-stack` as a dependency via the OCI registry (`oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`)
- Enable and configure the following components in `values.yaml`:
  - **Prometheus Operator** — manages Prometheus and AlertManager CRDs
  - **Prometheus** — metrics collection and storage
  - **Grafana** — dashboards and visualization
  - **AlertManager** — alert routing and notification
- Update `charts/Makefile` with an `obs-deploy` target that installs/upgrades the stack
- Update `charts/Chart.yaml` with the correct dependency reference

## Capabilities

### New Capabilities

- `prometheus-stack`: Deploys `kube-prometheus-stack` via OCI Helm dependency into the local devbox Kubernetes cluster, with Prometheus Operator, Prometheus, Grafana, and AlertManager enabled

### Modified Capabilities

<!-- No existing specs to modify -->

## Impact

- `charts/Chart.yaml` — adds `kube-prometheus-stack` as an OCI dependency
- `charts/values.yaml` — adds component enable flags and basic configuration
- `charts/Makefile` — adds `obs-deploy` target (referenced by root Makefile)
- Kubernetes cluster (devbox) — installs CRDs and workloads from `kube-prometheus-stack`
- No changes to application code, docker-compose, or backend services
