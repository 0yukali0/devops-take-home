#!/usr/bin/env bash
# Build the blue image, start infrastructure, boot the blue app container,
# and confirm it is healthy before handing off to the green deploy step.
set -e

BLUE=mt-blue

echo "--- Build blue image ---"
make image VERSION=$BLUE

echo "--- Start infrastructure (traefik + databases) ---"
VERSION=$BLUE docker compose up -d traefik mongo postgres redis

echo "--- Start blue app container ---"
docker run -d --name app --network backend_default \
  -e MONGO_URI=mongodb://mongo:27017/ems \
  -e PG_URI=postgresql://postgres:postgres@postgres:5432/ems \
  -e REDIS_URL=redis://redis:6379 \
  backend:$BLUE

echo "Waiting for app to be healthy..."
for i in $(seq 20); do curl -sf http://localhost/health >/dev/null 2>&1 && break || sleep 2; done
curl -sf http://localhost/health \
  || { echo "FAIL: blue app not healthy" >&2; exit 1; }
echo "PASS: blue app healthy"
