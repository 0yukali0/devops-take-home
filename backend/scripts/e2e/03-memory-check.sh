#!/usr/bin/env bash
# [9.4] Memory sanity — verify no container has restarted unexpectedly.
# docker compose enforces mem_limit as a hard cap; OOM events cause container
# restarts, so RestartCount > 0 is the reliable OOM signal.
set -e

echo "--- [9.4] Memory sanity: checking for OOM restarts ---"
BAD=$(docker compose ps -q \
  | xargs -r docker inspect --format '{{.Name}} restarts={{.RestartCount}}' \
  | awk -F= '$2+0>0 {print}')

if [ -n "$BAD" ]; then
  echo "FAIL [9.4]: containers with unexpected restarts (possible OOM):" >&2
  echo "$BAD" >&2
  exit 1
fi

docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
echo "PASS [9.4]: no OOM restarts detected"
