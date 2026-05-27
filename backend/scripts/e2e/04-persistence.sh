#!/usr/bin/env bash
# [9.5] Data persistence — confirm device data survives docker compose down && up.
# Intentionally does NOT re-seed after restart so the count comparison is meaningful.
set -e

# Resolve volume base path from .env (falls back to /tmp).
set -a; [ -f .env ] && . ./.env; set +a
VPATH=${VOLUME_PATH:-/tmp}

echo "--- [9.5] Data persistence: dev-stop → up (no seed) → verify device count ---"

DEVICE_COUNT=$(curl -sf http://localhost/api/devices \
  | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null \
  || echo "unknown")
echo "  Devices before restart: $DEVICE_COUNT"

make dev-stop

mkdir -p "$VPATH/mongo-data" "$VPATH/postgres-data" "$VPATH/redis-data"
docker compose up -d

echo "Waiting for app after restart (up to 60s)..."
for i in $(seq 30); do
  curl -sf http://localhost/health >/dev/null 2>&1 && break || sleep 2
done
curl -sf http://localhost/health \
  || { echo "FAIL [9.5]: app not healthy after restart" >&2; exit 1; }

DEVICE_COUNT_AFTER=$(curl -sf http://localhost/api/devices \
  | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null \
  || echo "unknown")
echo "  Devices after restart:  $DEVICE_COUNT_AFTER"

[ "$DEVICE_COUNT" = "$DEVICE_COUNT_AFTER" ] \
  || { echo "FAIL [9.5]: device count changed (before=$DEVICE_COUNT, after=$DEVICE_COUNT_AFTER)" >&2; exit 1; }

echo "PASS [9.5]: $DEVICE_COUNT_AFTER devices persisted across restart"
