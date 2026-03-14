#!/bin/sh
set -eu

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

run_daemon_forever() {
  while true; do
    if sh /etc/services.d/daemon/run; then
      exit_code=0
    else
      exit_code=$?
    fi
    echo "[start] $(timestamp) daemon exited with code ${exit_code}; restarting in 5s"
    sleep 5
  done
}

echo "[start] Running init"
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

echo "[start] Launching daemon"
run_daemon_forever &

echo "[start] Launching web"
exec sh /etc/services.d/web/run
