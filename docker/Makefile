.PHONY: cluster-start
cluster-start: cluster-stop
	kind create cluster --name dev --config cluster.yaml

.PHONY: cluster-stop
cluster-stop:
	kind delete cluster --name dev