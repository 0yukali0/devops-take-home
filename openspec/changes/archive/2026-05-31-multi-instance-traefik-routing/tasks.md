## 1. Traefik Static Config

- [x] 1.1 Add `providers.docker` section to `backend/traefik/traefik.yml` with `exposedByDefault: false` and `network: traefik_net`, keeping existing `providers.file` config intact

## 2. Docker Compose Changes

- [x] 2.1 Add Traefik Docker labels to the `app` service in `backend/docker-compose.yaml`: `traefik.enable=true`, router rule `Host("instance-${INSTANCE:-1}.localhost")`, entrypoint `web`, service port `3000`, and `traefik.docker.network=traefik_net`
- [x] 2.2 Remove `container_name: app` and `ports: ["3000:3000"]` from the `app` service; replace with `expose: ["3000"]`
- [x] 2.3 Add `traefik_net` to the `app` service's `networks` list (alongside existing internal network)
- [x] 2.4 Add `traefik_net` to the `traefik` service's `networks` list
- [x] 2.5 Update the `networks` section: add `name: ${BACKEND_NET:-backend_default}` to the internal network definition and add `traefik_net` as `external: true`
- [x] 2.6 Namespace volume bind-mount paths for mongo, postgres, and redis services: append `${INSTANCE_SUFFIX:-}` to each data directory path
- [x] 2.7 Update Alloy service environment variables: set domain to `${ALLOY_DOMAIN}-${INSTANCE:-1}` and tenant ID to `${ALLOY_DOMAIN}-${ALLOY_STAGE}-${INSTANCE:-1}`

## 3. Backend Makefile

- [x] 3.1 Add `INSTANCE ?= 1` and `VOLUME ?= /tmp` variables at the top of `backend/Makefile`
- [x] 3.2 Add conditional `COMPOSE`, `BACKEND_NET`, and `INST_SUFFIX` variable blocks: INSTANCE=1 uses plain `docker compose`; INSTANCE≥2 sets `INSTANCE=$(INSTANCE) BACKEND_NET=backend-$(INSTANCE) INSTANCE_SUFFIX=-$(INSTANCE)` and passes `-p backend-$(INSTANCE)`
- [x] 3.3 Add conditional `SERVICES` variable: empty for INSTANCE=1 (starts all services including Traefik); `app collector mongo postgres redis alloy` for INSTANCE≥2 (excludes Traefik)
- [x] 3.4 Add `ensure-traefik-net` phony target that runs `docker network create traefik_net 2>/dev/null || true`
- [x] 3.5 Update `dev-start` target: depend on `ensure-traefik-net`, create namespaced volume directories using `INST_SUFFIX`, run `$(COMPOSE) up -d $(SERVICES)`, then seed with `$(COMPOSE) exec app node dist/seed.js`
- [x] 3.6 Update `dev-stop` target to use `$(COMPOSE) down`
- [x] 3.7 Add `dev-obs-stop` phony target with stop-all logic (iterates instances 2–5 and default project); `dev-stop-all` removed per design update
- [x] 3.8 Add `dev-obs-start` phony target that runs `make dev-start INSTANCE=1`, `make dev-start INSTANCE=2`, and `make dev-start INSTANCE=3` in sequence
- [x] 3.9 `dev-obs-stop` contains stop-all logic directly (no separate delegate)
- [x] 3.10 Update `migration-test` target to depend on `ensure-traefik-net`

## 4. Root Makefile

- [x] 4.1 Add `INSTANCE` variable that reads the second word of `$(MAKECMDGOALS)`, defaulting to `1`
- [x] 4.2 Update `dev-start` and `dev-stop` targets to forward `INSTANCE=$(INSTANCE)` to the backend Makefile
- [x] 4.3 Add `dev-obs-start` target that delegates to `make -C backend dev-obs-start`
- [x] 4.4 Add `dev-obs-stop` target that delegates to `make -C backend dev-obs-stop`
- [x] 4.5 Add a catch-all `%: @:` target to absorb numeric positional arguments (e.g., `2`, `3`) so Make does not error on unrecognized targets

## 5. Migration Script

- [x] 5.1 Add `docker network create traefik_net 2>/dev/null || true` before the `docker compose up` call in `backend/scripts/migration/01-start-blue.sh`

## 6. Verification

- [x] 6.1 Run `make dev-start 1` and verify `curl http://localhost/health` and `curl -H "Host: instance-1.localhost" http://localhost/health` both return 200
- [x] 6.2 Run `make dev-start 2` and verify `curl -H "Host: instance-2.localhost" http://localhost/health` returns 200 while instance 1 remains functional
- [x] 6.3 Run `make dev-obs-start` from a clean state and verify all three instances are routable
- [x] 6.4 Run `make dev-obs-stop` and verify all containers are removed
- [x] 6.5 Run `make e2e-test` and confirm all e2e tests pass
- [x] 6.6 Run `make migration-test` and confirm all migration tests pass
