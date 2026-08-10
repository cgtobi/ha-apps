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

# Lowercase uppercase activity-file extensions in the watch dir (e.g. Garmin
# "*.FIT") so the upstream importer can read and delete them. Without this a
# single uppercase-extension file is listed but never readable, aborting every
# 5-minute import forever. See sfs-normalize-watch.sh for the full rationale.
run_watch_normalize_forever() {
  while true; do
    sh /usr/local/bin/sfs-normalize-watch.sh >/dev/null 2>&1 || true
    sleep 15
  done
}

log "Running init"
sh /etc/cont-init.d/00-init

# 00-init runs as a child above, so its exports do not reach this process. The
# v5 upstream image has no s6-overlay, so re-export the runtime env here (from
# options.json plus the two files 00-init persisted under /data/runtime) so the
# daemon, background reconcile and web service all inherit it.
OPTIONS_FILE="/data/options.json"
if [ -f "$OPTIONS_FILE" ]; then
  # Only export the Strava creds when non-empty. In files mode they are blank,
  # and exporting a blank value would override the upstream services.yaml
  # env(STRAVA_CLIENT_ID) 'replace-me' default with an empty string, making the
  # DI container build StravaClientId('') and throw "can not be empty" on /admin.
  # Leaving them unset lets Symfony fall back to that non-empty default.
  _strava_client_id="$(jq -r '.strava_client_id // ""' "$OPTIONS_FILE")"
  _strava_client_secret="$(jq -r '.strava_client_secret // ""' "$OPTIONS_FILE")"
  _strava_refresh_token="$(jq -r '.strava_refresh_token // ""' "$OPTIONS_FILE")"
  [ -n "$_strava_client_id" ]     && export STRAVA_CLIENT_ID="$_strava_client_id"
  [ -n "$_strava_client_secret" ] && export STRAVA_CLIENT_SECRET="$_strava_client_secret"
  [ -n "$_strava_refresh_token" ] && export STRAVA_REFRESH_TOKEN="$_strava_refresh_token"
  export TZ="$(jq -r '.tz // ""' "$OPTIONS_FILE")"
  export CADDY_LOG_LEVEL="$(jq -r '.caddy_log_level // ""' "$OPTIONS_FILE")"
  export IMPORT_MODE="$(jq -r '.import_mode // "stravaApi"' "$OPTIONS_FILE")"
  export ADMIN_USERNAME="$(jq -r '.admin_username // "admin"' "$OPTIONS_FILE")"
fi

# APP_URL, APP_SECRET and ADMIN_PASSWORD_HASH are resolved by 00-init (APP_URL is
# defaulted when the option is empty; the other two are generated/computed) and
# persisted under /data/runtime. Read them back here so the services get the same
# values 00-init used. Guard with -s so an unexpected empty file does not export a
# blank value (a blank APP_URL would make the app's AppUrl value object throw).
if [ -s /data/runtime/app_url ]; then
  export APP_URL="$(cat /data/runtime/app_url)"
fi
if [ -s /data/runtime/app_secret ]; then
  export APP_SECRET="$(cat /data/runtime/app_secret)"
fi
if [ -s /data/runtime/admin_password_hash ]; then
  export ADMIN_PASSWORD_HASH="$(cat /data/runtime/admin_password_hash)"
fi

sh /usr/local/bin/sfs-startup-preflight.sh

# Normalise any files already waiting before the daemon's first import, then keep
# normalising newly-dropped files on a short loop.
sh /usr/local/bin/sfs-normalize-watch.sh >/dev/null 2>&1 || true
log "Launching watch-dir extension normaliser"
run_watch_normalize_forever &

log "Launching daemon"
run_daemon_forever &

# Run the slow data reconcile (the startup Strava import) in the background so the
# web server (and /healthz) can come up immediately. init already ran the fast
# config phase (DB migration only; config now lives in the DB), so the DB schema
# is ready; pages 404 until the first import lands, instead of the watchdog seeing
# a closed port for the whole import and restarting the addon. In files mode the
# data phase is a no-op — the daemon owns the watch dir.
log "Launching background data reconcile (startup import)"
( SFS_RECONCILE_PHASE=data sh /usr/local/bin/sfs-reconcile-config.sh \
    >/tmp/sfs-data-reconcile.log 2>&1 ) &

log "Launching web"
exec sh /etc/services.d/web/run
