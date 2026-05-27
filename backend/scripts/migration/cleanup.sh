#!/usr/bin/env bash
# Idempotent cleanup for migration-test.
# Called once at the start (fresh environment) and again via EXIT trap.
docker stop app app-new           2>/dev/null || true
docker rm   app app-new           2>/dev/null || true
docker compose down               2>/dev/null || true
docker rmi  backend:mt-blue backend:mt-green 2>/dev/null || true
# Wipe bind-mount data so the next run always gets a fresh MongoDB init.
# shellcheck disable=SC1091
[[ -f .env ]] && { set -a; source .env; set +a; }
VPATH="${VOLUME_PATH:-/tmp}"
# Best-effort removal; files created inside containers are root-owned so this
# may only partially succeed — that's fine, || true prevents the cleanup trap
# from masking a test success with a spurious non-zero exit code.
rm -rf "${VPATH}/mongo-data" "${VPATH}/postgres-data" "${VPATH}/redis-data" 2>/dev/null || true
