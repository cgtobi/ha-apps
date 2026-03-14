#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"
CONFIG_DIR="/data/config/app"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
CHALLENGE_HISTORY_FILE="/data/storage/files/strava-challenge-history.html"
LOCK_DIR="/tmp/sfs-config-reconcile.lock"
RUNTIME_DIR="/data/runtime"
STATUS_FILE="${RUNTIME_DIR}/reconcile.status"

if [ ! -f "$OPTIONS_FILE" ]; then
  exit 0
fi

APP_CONFIG_YAML="$(jq -r '.app_config_yaml // ""' "$OPTIONS_FILE")"
if [ -z "$APP_CONFIG_YAML" ]; then
  exit 0
fi

mkdir -p "$CONFIG_DIR"
mkdir -p /data/storage/files
mkdir -p "$RUNTIME_DIR"

# Simple lock to avoid concurrent writes from web/daemon start scripts.
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  sleep 0.1
done
cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

CANDIDATE_CONFIG="${CONFIG_FILE}.candidate"
if ! php /usr/local/share/sfs/render-app-config.php "$OPTIONS_FILE" "$CANDIDATE_CONFIG" >/tmp/sfs-config-render.log 2>&1; then
  echo "FATAL: Could not render app config from add-on options"
  sed -n '1,5p' /tmp/sfs-config-render.log || true
  rm -f "$CANDIDATE_CONFIG"
  exit 1
fi

if ! php /usr/local/share/sfs/validate-app-config.php "$CANDIDATE_CONFIG" >/tmp/sfs-config-validate.log 2>&1; then
  echo "FATAL: Invalid app_config_yaml in add-on options"
  sed -n '1,5p' /tmp/sfs-config-validate.log || true
  rm -f "$CANDIDATE_CONFIG"
  exit 1
fi

CURRENT_SHA=""
if [ -f "$CONFIG_FILE" ]; then
  CURRENT_SHA="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"
fi
CANDIDATE_SHA="$(sha256sum "$CANDIDATE_CONFIG" | awk '{print $1}')"

if [ "$CURRENT_SHA" != "$CANDIDATE_SHA" ]; then
  mv "$CANDIDATE_CONFIG" "$CONFIG_FILE"
  CHANGED="true"
else
  rm -f "$CANDIDATE_CONFIG"
  CHANGED="false"
fi

CHALLENGE_HISTORY_HTML="$(jq -r '.strava_challenge_history_html // ""' "$OPTIONS_FILE")"
if [ -n "$CHALLENGE_HISTORY_HTML" ]; then
  printf '%s\n' "$CHALLENGE_HISTORY_HTML" > "$CHALLENGE_HISTORY_FILE"
  echo "[reconcile] Updated ${CHALLENGE_HISTORY_FILE} from add-on options"
fi

if [ -f /var/www/bin/console ]; then
  echo "[reconcile] Running doctrine migrations"
  if ! (cd /var/www && php bin/console doctrine:migrations:migrate --no-interaction >/tmp/sfs-migrate.log 2>&1); then
    echo "WARN: Failed to run doctrine migrations during config reconcile"
    sed -n '1,10p' /tmp/sfs-migrate.log || true
  else
    echo "[reconcile] Doctrine migrations finished"
    echo "[reconcile] Running app:strava:build-files"
    if ! (cd /var/www && php bin/console app:strava:build-files >/tmp/sfs-build-files.log 2>&1); then
      echo "WARN: Failed to run app:strava:build-files during config reconcile"
      sed -n '1,10p' /tmp/sfs-build-files.log || true
    else
      echo "[reconcile] app:strava:build-files finished"
    fi
  fi
fi

{
  printf 'updated_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'changed=%s\n' "$CHANGED"
  printf 'config_sha256=%s\n' "$CANDIDATE_SHA"
} > "$STATUS_FILE"
