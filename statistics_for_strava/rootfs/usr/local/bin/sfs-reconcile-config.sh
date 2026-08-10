#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"
LOCK_DIR="/tmp/sfs-config-reconcile.lock"
RUNTIME_DIR="/data/runtime"
STATUS_FILE="${RUNTIME_DIR}/reconcile.status"
STARTUP_MARKER_FILE="${RUNTIME_DIR}/health.startup"
IMPORT_STARTUP_STAMP_FILE="${RUNTIME_DIR}/reconcile.import.startup"
MIGRATE_OK_FILE="${RUNTIME_DIR}/reconcile.migrate.ok"

# Reconcile runs in phases so the slow data work (import) can run in the
# background after the web server is already listening, instead of blocking boot
# and starving the HA watchdog:
#   config  - migrate DB, write status (fast; pre-serve)
#   data    - startup import (slow; backgrounded)
#   full    - config then data (default; back-compat for direct callers)
#
# There is no build phase (and no ingress rewrite phase): v5.2.0 removed
# pre-built HTML/API output, so pages are rendered per request and the add-on no
# longer post-processes generated files.
PHASE="${SFS_RECONCILE_PHASE:-full}"

timestamp_utc() {
  date +%Y-%m-%dT%H:%M:%S%z
}

log_msg() {
  printf '%s %s\n' "$(timestamp_utc)" "$*"
}

warn_msg() {
  log_msg "WARN: $*"
}

is_upstream_mutex_conflict() {
  log_file="$1"
  grep -Fq 'Lock "importDataOrBuildApp" is already acquired' "$log_file"
}

run_console_command() {
  log_file="$1"
  shift
  if (cd /var/www && php bin/console "$@" >"$log_file" 2>&1); then
    return 0
  fi
  cmd_rc=$?
  if is_upstream_mutex_conflict "$log_file"; then
    # Reserve rc=10 for upstream mutex contention so callers can handle it explicitly.
    return 10
  fi
  return "$cmd_rc"
}

if [ ! -f "$OPTIONS_FILE" ]; then
  exit 0
fi

IMPORT_MODE="$(jq -r '.import_mode // "stravaApi"' "$OPTIONS_FILE")"
export IMPORT_MODE
STRAVA_CLIENT_ID="$(jq -r '.strava_client_id // ""' "$OPTIONS_FILE")"
STRAVA_CLIENT_SECRET="$(jq -r '.strava_client_secret // ""' "$OPTIONS_FILE")"
STRAVA_REFRESH_TOKEN="$(jq -r '.strava_refresh_token // ""' "$OPTIONS_FILE")"
TZ_VALUE="$(jq -r '.tz // ""' "$OPTIONS_FILE")"

# Reconcile can run during init before s6 environment propagation.
# Export required runtime vars here so Symfony console commands have credentials.
if [ -n "$STRAVA_CLIENT_ID" ]; then
  export STRAVA_CLIENT_ID
fi
if [ -n "$STRAVA_CLIENT_SECRET" ]; then
  export STRAVA_CLIENT_SECRET
fi
if [ -n "$STRAVA_REFRESH_TOKEN" ]; then
  export STRAVA_REFRESH_TOKEN
fi
if [ -n "$TZ_VALUE" ]; then
  export TZ="$TZ_VALUE"
fi

mkdir -p /data/storage/files
mkdir -p "$RUNTIME_DIR"

# Lock to serialize writes from the init / background data reconcile. mkdir is
# the atomic primitive. A live holder (e.g. a slow background import) is waited
# for. A holder that died without running its trap (SIGKILL / OOM / power-cut)
# would otherwise orphan the lock dir forever, so steal it once the recorded PID
# is gone AND the dir is older than any real reconcile could plausibly take.
LOCK_PID_FILE="${LOCK_DIR}/owner.pid"
LOCK_STALE_MIN=20

acquire_lock() {
  while true; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s\n' "$$" > "$LOCK_PID_FILE" 2>/dev/null || true
      return 0
    fi
    holder="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
      :  # holder alive — wait for it
    elif [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin "+${LOCK_STALE_MIN}" 2>/dev/null)" ]; then
      warn_msg "Stealing stale reconcile lock (holder=${holder:-unknown})"
      rm -rf "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
    # Holder dead but lock still fresh (tiny mkdir->pid write window), or holder
    # alive: back off and retry.
    sleep 0.2
  done
}

acquire_lock
cleanup() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ "$PHASE" = "config" ] || [ "$PHASE" = "full" ]; then
  # Record migration outcome so the (possibly separate, backgrounded) data phase
  # only imports against a schema that migrated cleanly. Cleared first so a stale
  # marker from a prior boot can never green-light the data phase.
  rm -f "$MIGRATE_OK_FILE"
  if [ -f /var/www/bin/console ]; then
    # Use app:db:migrate (not doctrine:migrations:migrate) so the migration
    # squash handler runs first. v4.8.8 squashed the migration history; on an
    # existing database the handler marks the squashed migration executed,
    # whereas a raw doctrine migrate would try to re-run the squashed
    # schema-create migration on a populated DB and fail. It also leaves the
    # schema reporting "at latest version", which the daemon's
    # #[RequiresUpToDateDatabaseSchema] commands require to not be blocked.
    # app:db:migrate also seeds config->DB on first boot.
    log_msg "[reconcile] Running database migrations"
    if ! (cd /var/www && php bin/console app:db:migrate --no-interaction >/tmp/sfs-migrate.log 2>&1); then
      warn_msg "Failed to run database migrations during config reconcile"
      sed -n '1,10p' /tmp/sfs-migrate.log || true
    else
      log_msg "[reconcile] Database migrations finished"
      : > "$MIGRATE_OK_FILE"
    fi
  fi

  # `changed` is vestigial since config-diff detection was removed in the v5
  # migration (config now lives in the DB); kept as a stable status-file shape.
  {
    printf 'updated_at=%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
    printf 'changed=%s\n' "true"
  } > "$STATUS_FILE"
fi

if [ "$PHASE" = "data" ] || [ "$PHASE" = "full" ]; then
  if [ ! -f /var/www/bin/console ]; then
    log_msg "[reconcile] Skipping data phase (Symfony console not found)"
  elif [ ! -f "$MIGRATE_OK_FILE" ]; then
    warn_msg "Skipping startup import (database migrations did not complete cleanly)"
  elif [ "$IMPORT_MODE" = "files" ]; then
    # In "files" mode the mandatory v5 daemon is the sole importer (it runs
    # app:cron:run-file-import every 5 min). If a startup run imported too, two
    # processes would work the shared watch dir; because the importer deletes each
    # file as it finishes, an overlap makes one process read a file the other has
    # already removed ("Unable to read ... watch/<file>: No such file"). Since
    # v5.2.0 there is no build step left to run here either, so the startup data
    # phase has nothing to do in this mode.
    log_msg "[reconcile] Skipping startup import in files mode (the daemon owns the watch dir)"
  else
    # In "stravaApi" mode there is no watch dir to contend for, so run an import
    # on startup to give an immediate first sync. Steady-state imports run via the
    # daemon's own cron.
    #
    # Run it at most once per startup: init runs the config phase on boot, the
    # backgrounded data phase runs this once. A fresh boot always runs because the
    # startup marker differs from the last stamp.
    RUN_IMPORT_NOW="true"
    if [ -r "$STARTUP_MARKER_FILE" ]; then
      CURRENT_STARTUP_MARKER="$(tr -d '\n' < "$STARTUP_MARKER_FILE" || true)"
      LAST_IMPORT_MARKER=""
      if [ -r "$IMPORT_STARTUP_STAMP_FILE" ]; then
        LAST_IMPORT_MARKER="$(tr -d '\n' < "$IMPORT_STARTUP_STAMP_FILE" || true)"
      fi

      if [ -n "$CURRENT_STARTUP_MARKER" ] && [ "$CURRENT_STARTUP_MARKER" = "$LAST_IMPORT_MARKER" ]; then
        RUN_IMPORT_NOW="false"
        log_msg "[reconcile] Skipping app:cron:run-strava-import (already attempted for this startup)"
      fi
    fi

    if [ "$RUN_IMPORT_NOW" = "true" ]; then
      # Record the startup this run covers so later reconciles this boot skip.
      if [ -r "$STARTUP_MARKER_FILE" ]; then
        tr -d '\n' < "$STARTUP_MARKER_FILE" > "$IMPORT_STARTUP_STAMP_FILE" || true
      fi

      log_msg "[reconcile] Running app:cron:run-strava-import --import"
      if run_console_command /tmp/sfs-import.log app:cron:run-strava-import --import; then
        log_msg "[reconcile] app:cron:run-strava-import finished"
      else
        RC=$?
        if [ "$RC" -eq 10 ]; then
          warn_msg "Skipped app:cron:run-strava-import (mutex already acquired by another process)"
        else
          warn_msg "Failed to run app:cron:run-strava-import (exit_code=${RC})"
        fi
        sed -n '1,40p' /tmp/sfs-import.log || true
      fi
    fi
  fi
fi
