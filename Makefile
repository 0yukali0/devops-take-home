.PHONY: image
VERSION  ?= dev
INSTANCE := $(word 2,$(MAKECMDGOALS))
ifeq ($(INSTANCE),)
  INSTANCE := 1
endif

image:
	make -C backend image VERSION=$(VERSION)

.PHONY: lint
lint:
	make -C charts lint
	make -C backend lint

.PHONY: dev-start
dev-start:
	make -C backend dev-start INSTANCE=$(INSTANCE)

.PHONY: dev-stop
dev-stop:
	make -C backend dev-stop INSTANCE=$(INSTANCE)

.PHONY: dev-obs-start
dev-obs-start:
	make -C backend dev-obs-start

.PHONY: dev-obs-stop
dev-obs-stop:
	make -C backend dev-obs-stop

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

# Absorb numeric positional args (e.g. the "2" in "make dev-start 2") so Make
# doesn't error with "No rule to make target '2'".
%:
	@:
