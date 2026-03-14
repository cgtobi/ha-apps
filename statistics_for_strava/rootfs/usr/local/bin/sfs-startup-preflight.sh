#!/bin/sh
set -eu

log() {
  echo "[preflight] $*"
}

warn() {
  echo "[preflight] WARN: $*"
}

CONFIG_FILE="/data/config/app/config.yaml"
BUILD_DIR="/data/build/html"
BUILD_INDEX="${BUILD_DIR}/index.html"
LOG_DIR="/data/storage/files/logs"
CHALLENGE_HISTORY_FILE="/data/storage/files/strava-challenge-history.html"
WWW_STORAGE_LINK="/var/www/storage"
RECONCILE_STATUS="/data/runtime/reconcile.status"

log "Running startup checks"

if [ -r "$CONFIG_FILE" ]; then
  log "OK config file readable: ${CONFIG_FILE}"
else
  warn "Config file missing or unreadable: ${CONFIG_FILE}"
fi

if [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ]; then
  log "OK log directory writable: ${LOG_DIR}"
else
  warn "Log directory missing or not writable: ${LOG_DIR}"
fi

if [ -d "$BUILD_DIR" ]; then
  log "OK build directory exists: ${BUILD_DIR}"
else
  warn "Build directory missing: ${BUILD_DIR}"
fi

if [ -f "$BUILD_INDEX" ]; then
  log "OK build entrypoint exists: ${BUILD_INDEX}"
else
  warn "Build entrypoint missing: ${BUILD_INDEX} (app may return 404 until build-files succeeds)"
fi

if [ -f /var/www/bin/console ]; then
  log "OK Symfony console found: /var/www/bin/console"
else
  warn "Symfony console missing: /var/www/bin/console"
fi

if [ -L "$WWW_STORAGE_LINK" ]; then
  log "OK storage symlink present: ${WWW_STORAGE_LINK}"
else
  warn "Storage symlink missing: ${WWW_STORAGE_LINK}"
fi

if [ -r "$CONFIG_FILE" ]; then
  app_url_line="$(grep -Em1 '^[[:space:]]*appUrl:[[:space:]]*' "$CONFIG_FILE" || true)"
  if [ -z "$app_url_line" ]; then
    warn "Could not find general.appUrl in ${CONFIG_FILE}"
  else
    app_url_value="$(printf '%s' "$app_url_line" | sed -E 's/^[[:space:]]*appUrl:[[:space:]]*["'\'']?([^"'\''[:space:]]+).*$/\1/')"
    log "general.appUrl=${app_url_value}"
    if [ "$app_url_value" = "http://CHANGE_ME:8080/" ] || [ "$app_url_value" = "http://CHANGE_ME:8080" ]; then
      warn "general.appUrl still uses placeholder value"
    fi
  fi
fi

if [ -r "$RECONCILE_STATUS" ]; then
  log "Reconcile status:"
  sed -n '1,3p' "$RECONCILE_STATUS" | sed 's/^/[preflight]   /'
else
  warn "Reconcile status file missing: ${RECONCILE_STATUS}"
fi

if [ -f "$CHALLENGE_HISTORY_FILE" ]; then
  if grep -q "OVERRIDE ME WITH HTML COPY/PASTED" "$CHALLENGE_HISTORY_FILE"; then
    warn "Challenge history file contains upstream placeholder marker"
  else
    log "OK challenge history file available: ${CHALLENGE_HISTORY_FILE}"
  fi
else
  warn "Challenge history file missing: ${CHALLENGE_HISTORY_FILE}"
fi

log "Startup checks complete"
