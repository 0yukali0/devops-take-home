.PHONY: image
VERSION ?= dev
image:
	docker build -t backend:$(VERSION) .

.PHONY: dev-start
dev-start: dev-stop image
	docker compose up -d
	docker compose exec app node dist/seed.js

.PHONY: dev-stop
dev-stop:
	docker compose down

.PHONY: deploy
deploy:
	@test -n "$(VERSION)" || (echo "VERSION is required: make deploy VERSION=<tag>" >&2; exit 1)
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

# End-to-end migration + blue-green deploy test for CI.
# Builds two image tags from the current source, starts infrastructure via
# docker compose, boots v1 as the live container, then deploys v2 through
# deploy.sh (which runs migration and does the full blue-green switch).
# Because both tags come from the same source, the second migration run is
# idempotent — deploy.sh must complete successfully and the app must be
# healthy at the end.
.PHONY: migration-test
migration-test:
	@echo "=== Migration + deploy integration test ==="
	@set -e; \
	BLUE=mt-blue; GREEN=mt-green; \
	cleanup() { \
		docker stop app app-new 2>/dev/null || true; \
		docker rm  app app-new 2>/dev/null || true; \
		docker compose down    2>/dev/null || true; \
		docker rmi backend:$$BLUE backend:$$GREEN 2>/dev/null || true; \
	}; \
	trap cleanup EXIT; \
	cleanup; \
	echo "--- Build blue image ---"; \
	$(MAKE) image VERSION=$$BLUE; \
	echo "--- Start infrastructure (traefik + databases) ---"; \
	VERSION=$$BLUE docker compose up -d traefik mongo postgres redis; \
	echo "--- Start blue app container ---"; \
	docker run -d --name app --network backend_default \
		-e MONGO_URI=mongodb://mongo:27017/ems \
		-e PG_URI=postgresql://postgres:postgres@postgres:5432/ems \
		-e REDIS_URL=redis://redis:6379 \
		backend:$$BLUE; \
	echo "Waiting for app to be healthy..."; \
	for i in $$(seq 20); do curl -sf http://localhost/health >/dev/null 2>&1 && break || sleep 2; done; \
	curl -sf http://localhost/health || { echo "FAIL: blue app not healthy" >&2; exit 1; }; \
	echo "PASS: blue app healthy"; \
	echo "--- Tag green image (same source = idempotent migration) ---"; \
	docker tag backend:$$BLUE backend:$$GREEN; \
	echo "--- Deploy green via deploy.sh (migration + blue-green switch) ---"; \
	./deploy.sh backend:$$GREEN; \
	echo "--- Verify app is healthy after deploy ---"; \
	for i in $$(seq 10); do curl -sf http://localhost/health >/dev/null 2>&1 && break || sleep 1; done; \
	curl -sf http://localhost/health || { echo "FAIL: app not healthy after deploy" >&2; exit 1; }; \
	echo "PASS: migration-test complete"
