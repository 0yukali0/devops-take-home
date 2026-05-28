#!/usr/bin/env bash
# Build the blue image, start infrastructure, boot the blue app container,
# and confirm it is healthy before handing off to the green deploy step.
set -e

BLUE=mt-blue

# Load credentials from .env (MONGO_URI, PG creds, etc.)
# shellcheck disable=SC1091
set -a; source .env; set +a

echo "--- Build blue image ---"
make image VERSION=$BLUE

echo "--- Create bind-mount directories for volumes ---"
VPATH="${VOLUME_PATH:-/tmp}"
mkdir -p "${VPATH}/mongo-data" "${VPATH}/postgres-data" "${VPATH}/redis-data"

echo "--- Start infrastructure (traefik + databases) ---"
VERSION=$BLUE docker compose up -d --wait traefik mongo postgres redis

echo "--- Start blue app container ---"
docker run -d --name app --network backend_default \
  -e MONGO_URI="$MONGO_URI" \
  -e PG_URI=postgresql://postgres:postgres@postgres:5432/ems \
  -e REDIS_URL=redis://redis:6379 \
  backend:$BLUE

echo "Waiting for app to be healthy..."
for i in $(seq 20); do curl -sf http://localhost/health >/dev/null 2>&1 && break || sleep 2; done
curl -sf http://localhost/health \
  || { echo "FAIL: blue app not healthy" >&2; exit 1; }
echo "PASS: blue app healthy"
