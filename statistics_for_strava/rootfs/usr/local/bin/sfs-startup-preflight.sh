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

LOG_DIR="/data/storage/files/logs"
WWW_STORAGE_LINK="/var/www/storage"
RECONCILE_STATUS="/data/runtime/reconcile.status"

log "Running startup checks"

if [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ]; then
  log "OK log directory writable: ${LOG_DIR}"
else
  warn "Log directory missing or not writable: ${LOG_DIR}"
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

# The ingress base path only reaches Symfony if x-forwarded-prefix is in the
# effective trusted_headers. That value comes from config/packages/zz-ha-ingress.yaml,
# which wins over upstream's framework.yaml only because Symfony loads
# config/packages in name order and ours sorts last. If that ever stops holding
# (upstream adds a later-sorting file of its own, our file gets renamed), the
# failure is silent: every URL comes out without the ingress prefix and the SPA
# renders nothing. Assert it here so the log says so instead.
TRUSTED_HEADERS="$(cd /var/www && php bin/console debug:container --parameter=kernel.trusted_headers --format=json 2>/dev/null || true)"
case "$TRUSTED_HEADERS" in
  *x-forwarded-prefix*)
    log "OK trusted_headers includes x-forwarded-prefix (ingress base path honored)"
    ;;
  '')
    warn "Could not read kernel.trusted_headers; skipped the ingress trusted-header check"
    ;;
  *)
    warn "trusted_headers is missing x-forwarded-prefix — ingress URLs will lose the base path. Check that config/packages/zz-ha-ingress.yaml still loads after upstream's framework.yaml"
    ;;
esac

if [ -r "$RECONCILE_STATUS" ]; then
  log "Reconcile status:"
  sed -n '1,3p' "$RECONCILE_STATUS" | sed "s/^/$(timestamp) [preflight]   /"
else
  warn "Reconcile status file missing: ${RECONCILE_STATUS}"
fi

log "Startup checks complete"
