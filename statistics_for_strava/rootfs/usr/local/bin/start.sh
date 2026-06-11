#!/bin/sh
set -eu

# Export TZ before anything logs so wrapper timestamps, child scripts and the
# FrankenPHP/Caddy process all emit local time instead of UTC.
if [ -f /data/options.json ]; then
  _tz="$(jq -r '.tz // ""' /data/options.json)"
  if [ -n "$_tz" ]; then
    export TZ="$_tz"
  fi
fi

timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

log() {
  echo "$(timestamp) [start] $*"
}

# Only emitted when CADDY_LOG_LEVEL=DEBUG; keeps the 30s ingress
# rewrite loop from spamming the log on every iteration.
debug_log() {
  case "$(printf '%s' "${CADDY_LOG_LEVEL:-}" | tr '[:upper:]' '[:lower:]')" in
    debug) echo "$(timestamp) [start] $*" ;;
  esac
}

run_daemon_forever() {
  while true; do
    if sh /etc/services.d/daemon/run; then
      exit_code=0
    else
      exit_code=$?
    fi
    log "daemon exited with code ${exit_code}; restarting in 5s"
    sleep 5
  done
}

run_ingress_rewrite_forever() {
  while true; do
    started_at="$(date +%s)"
    debug_log "ingress rewrite loop started"
    if ! SFS_RECONCILE_REWRITE_ONLY=1 sh /usr/local/bin/sfs-reconcile-config.sh >/tmp/sfs-rewrite-loop.log 2>&1; then
      log "ingress rewrite loop failed; showing recent output"
      tail -n 20 /tmp/sfs-rewrite-loop.log || true
    else
      finished_at="$(date +%s)"
      duration_seconds=$((finished_at - started_at))
      debug_log "ingress rewrite loop finished in ${duration_seconds}s"
    fi
    sleep 30
  done
}

log "Running init"
sh /etc/cont-init.d/00-init

OPTIONS_FILE="/data/options.json"
if [ -f "$OPTIONS_FILE" ]; then
  export STRAVA_CLIENT_ID="$(jq -r '.strava_client_id // ""' "$OPTIONS_FILE")"
  export STRAVA_CLIENT_SECRET="$(jq -r '.strava_client_secret // ""' "$OPTIONS_FILE")"
  export STRAVA_REFRESH_TOKEN="$(jq -r '.strava_refresh_token // ""' "$OPTIONS_FILE")"
  export TZ="$(jq -r '.tz // ""' "$OPTIONS_FILE")"
  export CADDY_LOG_LEVEL="$(jq -r '.caddy_log_level // ""' "$OPTIONS_FILE")"
fi

sh /usr/local/bin/sfs-startup-preflight.sh

log "Launching ingress rewrite loop"
run_ingress_rewrite_forever &

log "Launching daemon"
run_daemon_forever &

# Run the slow data reconcile (import + build-files) in the background so the
# web server (and /healthz) can come up immediately. init already ran the fast
# config phase (render/validate/migrate), so config and the DB schema are ready;
# pages 404 with a "building" state only until the first build lands, instead of
# the watchdog seeing a closed port for the whole import and restarting the addon.
log "Launching background data reconcile (import + build)"
( SFS_RECONCILE_PHASE=data sh /usr/local/bin/sfs-reconcile-config.sh \
    >/tmp/sfs-data-reconcile.log 2>&1 ) &

log "Launching web"
exec sh /etc/services.d/web/run
