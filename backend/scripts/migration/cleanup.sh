#!/usr/bin/env bash
# Idempotent cleanup for migration-test.
# Called once at the start (fresh environment) and again via EXIT trap.
docker stop app app-new           2>/dev/null || true
docker rm   app app-new           2>/dev/null || true
docker compose down               2>/dev/null || true
docker rmi  backend:mt-blue backend:mt-green 2>/dev/null || true
