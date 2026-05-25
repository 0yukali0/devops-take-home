## Context

The project has a `charts/` directory containing a bare Helm chart scaffold (`Chart.yaml`, empty `values.yaml`, empty `templates/`). The root `Makefile` calls `make -C charts obs-deploy` as part of `devbox-start`, but the charts directory has no `Makefile` and no observability stack defined. The devbox cluster is a `kind` cluster named `dev` (managed via `make -C docker cluster-start`).

The goal is to wire up `kube-prometheus-stack` from the prometheus-community OCI registry so that running `make devbox-start` results in a working monitoring stack inside the kind cluster.

## Goals / Non-Goals

**Goals:**
- Declare `kube-prometheus-stack` as a Helm chart dependency sourced from `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`
- Enable Prometheus Operator, Prometheus, Grafana, and AlertManager via `values.yaml`
- Provide an `obs-deploy` Makefile target that runs dependency resolution then installs/upgrades the stack
- Keep configuration minimal and devbox-appropriate (no production sizing, no persistent storage required)

**Non-Goals:**
- Configuring remote_write or scraping edge sites (that belongs to Ticket 3 / observability pipeline work)
- Persistent volume claims for Prometheus or Grafana data
- TLS/ingress configuration
- Custom Grafana dashboards or alert rules
- Production-grade resource limits or HA configuration

## Decisions

### OCI dependency vs. traditional Helm repo

**Decision:** Use OCI (`oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`) as the chart source in `Chart.yaml` dependencies.

**Rationale:** OCI registries are the modern standard for Helm chart distribution and don't require running `helm repo update`. Avoids the stateful `helm repo add` step.

**Alternative considered:** `helm repo add prometheus-community https://prometheus-community.github.io/helm-charts` — works but adds a stateful setup step that OCI avoids.

### Umbrella chart vs. direct install

**Decision:** Keep the existing umbrella chart structure (`charts/Chart.yaml`) and add `kube-prometheus-stack` as a dependency.

**Rationale:** The root `Makefile` already treats `charts/` as the deployment unit via `make -C charts obs-deploy`. Maintaining an umbrella chart allows additional components to be added later without changing the top-level invocation.

### Dependency resolution command in obs-deploy

**Decision:** The `obs-deploy` target will run `helm dependency build` if `Chart.lock` exists, otherwise `helm dependency update`, then `helm upgrade --install`.

**Rationale:** `helm dependency build` is faster and reproducible when a lock file is already present. `helm dependency update` resolves and writes the lock file on first run or when dependencies change. This pattern is idiomatic for Helm umbrella charts.

### Release name

**Decision:** Use `metric-dashboard` as the Helm release name.

**Rationale:** Specified by project convention.

### Namespace

**Decision:** Deploy into a dedicated `monitoring` namespace, created with `--create-namespace`.

**Rationale:** Keeps observability workloads isolated from application workloads. Standard convention for kube-prometheus-stack.

### Storage for Prometheus and Grafana

**Decision:** Override storage to `emptyDir` in `values.yaml`.

**Rationale:** The `kind` cluster created by `docker/cluster.yaml` may not have a default StorageClass. Using `emptyDir` avoids PVC binding failures at the cost of data persistence, which is acceptable for a local devbox.

## Risks / Trade-offs

- [OCI pull requires internet access] → Not a concern for local devbox; would need a registry mirror for air-gapped environments.
- [kube-prometheus-stack installs many CRDs] → Acceptable for devbox. CRDs remain after `helm uninstall` and require `kubectl delete crd` for full cleanup.
- [Grafana default credentials] → Default `admin/prom-operator` are fine for local devbox only.
- [emptyDir storage] → Prometheus and Grafana data is lost on pod restart; acceptable for devbox use.

## Migration Plan

1. Update `charts/Chart.yaml` — add `kube-prometheus-stack` as an OCI dependency
2. Update `charts/values.yaml` — enable the four components, set emptyDir storage
3. Create `charts/Makefile` — add `obs-deploy` target:
   - If `Chart.lock` exists: `helm dependency build`; else: `helm dependency update`
   - `helm upgrade --install metric-dashboard . -n monitoring --create-namespace`
4. Run `make devbox-start` — verifies cluster starts and stack deploys cleanly

Rollback: `helm uninstall metric-dashboard -n monitoring` removes the release. Delete CRDs manually if a clean teardown is needed.
