CLUSTER_NAME ?= devbox

.PHONY: obs-deploy
obs-deploy:
	@if [ -f Chart.lock ]; then \
		helm dependency build; \
	else \
		helm dependency update; \
	fi
	helm upgrade --install metric-dashboard . -n monitoring --create-namespace --set alloy.clusterName=$(CLUSTER_NAME)
