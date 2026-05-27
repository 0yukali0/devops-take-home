#!/usr/bin/env bash
# Tag the green image (same source as blue = idempotent migration), deploy via
# deploy.sh (runs migration + blue-green switch), and verify the app is healthy.
set -e

BLUE=mt-blue
GREEN=mt-green

echo "--- Tag green image (same source = idempotent migration) ---"
docker tag backend:$BLUE backend:$GREEN

echo "--- Deploy green via deploy.sh (migration + blue-green switch) ---"
./deploy.sh backend:$GREEN

echo "--- Verify app is healthy after deploy ---"
for i in $(seq 10); do curl -sf http://localhost/health >/dev/null 2>&1 && break || sleep 1; done
curl -sf http://localhost/health \
  || { echo "FAIL: app not healthy after deploy" >&2; exit 1; }
echo "PASS: green app healthy after deploy"
