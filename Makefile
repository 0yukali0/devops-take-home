.PHONY: image
VERSION ?= dev
image:
	make -C backend image VERSION=$(VERSION)

.PHONY: lint
lint:
	make -C charts lint
	make -C backend lint

.PHONY: dev-start
dev-start:
	make -C backend dev-start

.PHONY: dev-stop
dev-stop:
	make -C backend dev-stop

.PHONY: devbox-start
devbox-start:
	make -C docker cluster-start
	make -C charts obs-deploy

.PHONY: devbox-stop
devbox-stop:
	make -C docker cluster-stop

.PHONY: migration-test
migration-test:
	make -C backend migration-test

.PHONY: e2e-test
e2e-test:
	make -C backend e2e-test