#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/nodejs-api"
REPO_DIR="$APP_DIR/repo"
COMPOSE_FILE="$REPO_DIR/infra/docker/compose.prod.yaml"
ACTIVE_FILE="$APP_DIR/active-color"
UPSTREAM_DIR="/etc/nginx/upstreams"
UPSTREAM_FILE="$UPSTREAM_DIR/nodejs-api-upstream.conf"

IMAGE_TAG="${1:?Usage: deploy.sh IMAGE_TAG}"

if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
  echo "Invalid image tag: $IMAGE_TAG" >&2
  exit 1
fi

IMAGE="ghcr.io/sandeep9526/nodejs-devops-setup:${IMAGE_TAG}"

cd "$REPO_DIR"

# Prevent overlapping deployments.
exec 9>/var/lock/nodejs-api-deploy.lock
flock -n 9 || {
  echo "Another deployment is already running." >&2
  exit 1
}

# The first deployment starts blue; later deployments use the inactive slot.
if [[ -f "$ACTIVE_FILE" ]]; then
  ACTIVE="$(cat "$ACTIVE_FILE")"
else
  ACTIVE="green"
fi

case "$ACTIVE" in
  blue)
    NEXT="green"
    NEXT_SERVICE="app-green"
    NEXT_PORT="3002"
    ;;
  green)
    NEXT="blue"
    NEXT_SERVICE="app-blue"
    NEXT_PORT="3001"
    ;;
  *)
    echo "Invalid active-color state: $ACTIVE" >&2
    exit 1
    ;;
esac

echo "Deploying $IMAGE to slot $NEXT ($NEXT_SERVICE)."

if [[ ! -f "$UPSTREAM_FILE" ]]; then
  echo "Missing Nginx upstream file: $UPSTREAM_FILE" >&2
  exit 1
fi

BACKUP="$(mktemp "$UPSTREAM_DIR/nodejs-api-backup.XXXXXX")"
cp "$UPSTREAM_FILE" "$BACKUP"

SWITCH_ATTEMPTED=0
CANDIDATE=""

restore_upstream() {
  echo "Restoring previous Nginx upstream."

  local restore
  restore="$(mktemp "$UPSTREAM_DIR/nodejs-api-restore.XXXXXX")"
  cp "$BACKUP" "$restore"
  mv "$restore" "$UPSTREAM_FILE"

  if nginx -t; then
    systemctl reload nginx || {
      echo "ERROR: Nginx reload failed while restoring the previous upstream." >&2
      return 1
    }
  else
    echo "ERROR: Restored Nginx configuration failed validation." >&2
    return 1
  fi
}

on_error() {
  local rc=$?
  trap - ERR
  set +e

  if [[ "$SWITCH_ATTEMPTED" -eq 1 ]]; then
    restore_upstream || true
  fi

  [[ -z "$CANDIDATE" ]] || rm -f "$CANDIDATE"
  rm -f "$BACKUP"
  exit "$rc"
}
trap on_error ERR

# Pull the image and start only the inactive Compose service.
docker pull "$IMAGE"
IMAGE_TAG="$IMAGE_TAG" docker compose -f "$COMPOSE_FILE" up -d "$NEXT_SERVICE"

# Wait up to 90 seconds for the new container to become healthy.
CONTAINER="nodejs-api-$NEXT"
DEADLINE=$((SECONDS + 90))

until [[ "$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || true)" == "healthy" ]]; do
  if (( SECONDS >= DEADLINE )); then
    echo "New container did not become healthy." >&2
    docker logs --tail 100 "$CONTAINER" || true
    exit 1
  fi
  sleep 3
done

# Prepare the replacement upstream in the same directory for an atomic rename.
CANDIDATE="$(mktemp "$UPSTREAM_DIR/nodejs-api-candidate.XXXXXX")"

cat > "$CANDIDATE" <<EOF
upstream nodejs_api {
    server 127.0.0.1:${NEXT_PORT};
    keepalive 16;
}
EOF

# Mark the switch as attempted before replacing the active upstream.
SWITCH_ATTEMPTED=1
mv "$CANDIDATE" "$UPSTREAM_FILE"
CANDIDATE=""

# If validation or reload fails, the error trap restores the old upstream.
nginx -t
systemctl reload nginx

# Record the active slot only after Nginx accepts the new upstream.
printf '%s\n' "$NEXT" > "${ACTIVE_FILE}.tmp"
mv "${ACTIVE_FILE}.tmp" "$ACTIVE_FILE"

SWITCH_ATTEMPTED=0
rm -f "$BACKUP"
trap - ERR

echo "Deployment successful: slot=$NEXT image=$IMAGE"
