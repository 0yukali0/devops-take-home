#!/usr/bin/env bash
# [9.1+9.2] Clean build, start all services, seed the database.
# Delegates to `make dev-start` (dev-stop → image → compose up -d → seed.js).
set -e

echo "--- [9.1+9.2] Clean build, start all services, seed (via dev-start) ---"
make dev-start

echo "Waiting for app HTTP to become healthy (up to 60s)..."
for i in $(seq 30); do
  curl -sf http://localhost/health >/dev/null 2>&1 && break || sleep 2
done
curl -sf http://localhost/health \
  || { echo "FAIL [9.1]: app not healthy after 60s" >&2; exit 1; }

echo "PASS [9.1]: all services started and healthy"
echo "PASS [9.2]: seed completed without auth errors"
