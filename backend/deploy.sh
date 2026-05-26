#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-}"
if [[ -z "$IMAGE" ]]; then
  echo "Usage: $0 <image:tag>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRAEFIK_DYNAMIC="$SCRIPT_DIR/traefik/dynamic"
LOG_FILE="$SCRIPT_DIR/deploy-$(date -u +%Y%m%dT%H%M%SZ).log"

log() {
  local line="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  echo "$line"
  echo "$line" >> "$LOG_FILE"
}

MONGO_URI="${MONGO_URI:-mongodb://mongo:27017/ems}"
PG_URI="${PG_URI:-postgresql://postgres:postgres@postgres:5432/ems}"

# 1. Verify image exists locally
if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
  log "ERROR: Image '$IMAGE' not found locally. Run: make image VERSION=<tag>"
  exit 1
fi
log "Image verified: $IMAGE"

# 2. Run migration
log "Running migration..."
if ! docker run --rm \
  --network backend_default \
  -e MONGO_URI="$MONGO_URI" \
  "$IMAGE" node dist/migrate/index.js; then
  log "ERROR: Migration failed — aborting deploy"
  exit 1
fi
log "Migration succeeded"

# 3. Start green container
log "Starting green container app-new on host port 3001..."
docker run -d \
  --name app-new \
  --network backend_default \
  -p 3001:3000 \
  -e MONGO_URI="$MONGO_URI" \
  -e PG_URI="$PG_URI" \
  "$IMAGE"

# 4. Health check loop (60s timeout, 3s interval)
log "Polling health on http://localhost:3001/health ..."
DEADLINE=$(( $(date +%s) + ${HEALTH_TIMEOUT:-60} ))
HEALTHY=false
while [[ $(date +%s) -lt $DEADLINE ]]; do
  if curl -sf http://localhost:3001/health > /dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 3
done

if [[ "$HEALTHY" != "true" ]]; then
  log "ROLLBACK: health check timed out after 60s — stopping app-new"
  docker stop app-new
  docker rm app-new
  exit 1
fi
log "Green container is healthy"

# 5. Switch Traefik atomically to green
log "Switching Traefik upstream to app-new..."
TMP=$(mktemp)
cat > "$TMP" <<'EOF'
http:
  routers:
    app:
      rule: "PathPrefix(`/`)"
      entryPoints:
        - web
      service: app-green

  services:
    app-green:
      loadBalancer:
        servers:
          - url: "http://app-new:3000"
EOF
mv "$TMP" "$TRAEFIK_DYNAMIC/app.yml"
log "Traefik config written; waiting for reload..."
# Give Traefik's file watcher time to pick up the change before blue is stopped.
sleep 2
log "Traefik now routing to app-new:3000"

# 6. Remove blue container
log "Stopping and removing blue container (app)..."
docker rm -f app

# 7. Restore canonical Traefik config first, then rename.
#    Order matters: write app:3000 while container is still app-new.
#    Traefik's ~1s file-watch delay means the rename completes before
#    Traefik switches, so there is no window where app-new is gone but
#    the config still references it.
log "Restoring canonical Traefik config (app:3000)..."
TMP=$(mktemp)
cat > "$TMP" <<'EOF'
http:
  routers:
    app:
      rule: "PathPrefix(`/`)"
      entryPoints:
        - web
      service: app-blue

  services:
    app-blue:
      loadBalancer:
        servers:
          - url: "http://app:3000"
EOF
mv "$TMP" "$TRAEFIK_DYNAMIC/app.yml"

# 8. Rename after config is written — by the time Traefik reloads, app exists.
log "Renaming app-new -> app..."
docker rename app-new app
log "Deploy complete"