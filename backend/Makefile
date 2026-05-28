.PHONY: image
VERSION ?= dev
VOLUME  ?= /tmp
image:
	docker build -t backend:$(VERSION) .

.PHONY: dev-start
dev-start: dev-stop image
	@set -a; [ -f .env ] && . ./.env; set +a; \
	VPATH=$${VOLUME_PATH:-$(VOLUME)}; \
	mkdir -p "$$VPATH/mongo-data" "$$VPATH/postgres-data" "$$VPATH/redis-data"
	docker compose up -d
	docker compose exec app node dist/seed.js

.PHONY: dev-stop
dev-stop:
	docker compose down

.PHONY: deploy
deploy:
	@test -n "$(VERSION)" || (echo "VERSION is required: make deploy VERSION=<tag>" >&2; exit 1)
	@set -a; [ -f .env ] && . ./.env; set +a; \
	VPATH=$${VOLUME_PATH:-$(VOLUME)}; \
	mkdir -p "$$VPATH/mongo-data" "$$VPATH/postgres-data" "$$VPATH/redis-data"
	./deploy.sh backend:$(VERSION)

.PHONY: lint
lint:
	pnpm install --frozen-lockfile
	pnpm lint

.PHONY: migrate
migrate:
	docker run --rm \
		--network backend_default \
		-e MONGO_URI=$${MONGO_URI:-mongodb://mongo:27017/ems} \
		backend:$(VERSION) node dist/migrate/index.js

# End-to-end validation test covering fix-ticket1-db-misconfiguration (9.x tasks).
#   9.1  Clean build — all services start and become healthy
#   9.2  Seed — completes without auth errors
#   9.3  API smoke — GET /health, /api/devices, /api/telemetry/latest all return 200
#   9.4  Memory sanity — no container has restarted (OOM would cause restarts)
#   9.5  Persistence — device data survives docker compose down && up
.PHONY: e2e-test
e2e-test:
	@echo "=== E2E Validation Test (tasks 9.1–9.5) ==="
	@set -e; \
	trap '$(MAKE) dev-stop 2>/dev/null || true' EXIT; \
	bash scripts/e2e/01-start.sh; \
	bash scripts/e2e/02-api-smoke.sh; \
	bash scripts/e2e/03-memory-check.sh; \
	bash scripts/e2e/04-persistence.sh; \
	echo ""; \
	echo "=== e2e-test PASSED: all 9.x validation steps complete ==="

# End-to-end migration + blue-green deploy test for CI.
# Builds two image tags from the current source, starts infrastructure via
# docker compose, boots v1 as the live container, then deploys v2 through
# deploy.sh (which runs migration and does the full blue-green switch).
# Because both tags come from the same source, the second migration run is
# idempotent — deploy.sh must complete successfully and the app must be
# healthy at the end.
.PHONY: migration-test
migration-test:
	@[ -f .env ] || { echo "No .env found — copying from .env.example"; cp .env.example .env; }
	@echo "=== Migration + deploy integration test ==="
	@set -e; \
	trap 'bash scripts/migration/cleanup.sh' EXIT; \
	bash scripts/migration/cleanup.sh; \
	bash scripts/migration/01-start-blue.sh; \
	bash scripts/migration/02-deploy-green.sh; \
	echo "PASS: migration-test complete"
