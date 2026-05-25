#!/bin/sh
set -eu

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  echo "$(timestamp) [start] $*"
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
    log "ingress rewrite loop started"
    if ! SFS_RECONCILE_REWRITE_ONLY=1 sh /usr/local/bin/sfs-reconcile-config.sh >/tmp/sfs-rewrite-loop.log 2>&1; then
      log "ingress rewrite loop failed; showing recent output"
      tail -n 20 /tmp/sfs-rewrite-loop.log || true
    else
      finished_at="$(date +%s)"
      duration_seconds=$((finished_at - started_at))
      log "ingress rewrite loop finished in ${duration_seconds}s"
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

log "Launching web"
exec sh /etc/services.d/web/run
