#!/bin/sh
set -eu

timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

log() {
  echo "$(timestamp) [preflight] $*"
}

warn() {
  echo "$(timestamp) [preflight] WARN: $*"
}

BUILD_DIR="/data/build/html"
BUILD_INDEX="${BUILD_DIR}/index.html"
LOG_DIR="/data/storage/files/logs"
WWW_STORAGE_LINK="/var/www/storage"
RECONCILE_STATUS="/data/runtime/reconcile.status"

log "Running startup checks"

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
  warn "Build entrypoint missing: ${BUILD_INDEX} (app may return 404 until the first import+build succeeds)"
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

if [ -r "$RECONCILE_STATUS" ]; then
  log "Reconcile status:"
  sed -n '1,3p' "$RECONCILE_STATUS" | sed "s/^/$(timestamp) [preflight]   /"
else
  warn "Reconcile status file missing: ${RECONCILE_STATUS}"
fi

log "Startup checks complete"
