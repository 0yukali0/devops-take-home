#!/usr/bin/env bash
# [9.3] API smoke tests — confirm all three endpoints return HTTP 200.
set -e

echo "--- [9.3] API smoke tests ---"
curl -sf http://localhost/health               -o /dev/null \
  || { echo "FAIL [9.3]: GET /health"                >&2; exit 1; }
curl -sf http://localhost/api/devices          -o /dev/null \
  || { echo "FAIL [9.3]: GET /api/devices"           >&2; exit 1; }
curl -sf http://localhost/api/telemetry/latest -o /dev/null \
  || { echo "FAIL [9.3]: GET /api/telemetry/latest"  >&2; exit 1; }

echo "PASS [9.3]: /health, /api/devices, /api/telemetry/latest all returned 200"
