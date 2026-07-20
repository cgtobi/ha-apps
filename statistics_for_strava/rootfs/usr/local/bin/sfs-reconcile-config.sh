#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"
LOCK_DIR="/tmp/sfs-config-reconcile.lock"
RUNTIME_DIR="/data/runtime"
STATUS_FILE="${RUNTIME_DIR}/reconcile.status"
STARTUP_MARKER_FILE="${RUNTIME_DIR}/health.startup"
IMPORT_STARTUP_STAMP_FILE="${RUNTIME_DIR}/reconcile.import.startup"
BUILD_START_MARKER_FILE="${RUNTIME_DIR}/reconcile.build.start"
INGRESS_REWRITE_MARKER_FILE="${RUNTIME_DIR}/ingress-rewrite.last"
MIGRATE_OK_FILE="${RUNTIME_DIR}/reconcile.migrate.ok"

# Reconcile runs in phases so the slow data work (import + build) can run in the
# background after the web server is already listening, instead of blocking boot
# and starving the HA watchdog:
#   config  - migrate DB, write status (fast; pre-serve)
#   data    - import+build (combined) + prune + ingress rewrites (slow; backgrounded)
#   rewrite - ingress path rewrites only (the 30s loop)
#   full    - config then data (default; back-compat for direct callers)
PHASE="${SFS_RECONCILE_PHASE:-full}"
if [ "${SFS_RECONCILE_REWRITE_ONLY:-0}" = "1" ]; then
  PHASE="rewrite"
fi

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

# Lock to serialize writes from the init / background data reconcile / 30s
# rewrite loop. mkdir is the atomic primitive. A live holder (e.g. a slow
# background import) is waited for. A holder that died without running its trap
# (SIGKILL / OOM / power-cut) would otherwise orphan the lock dir forever, so
# steal it once the recorded PID is gone AND the dir is older than any real
# reconcile could plausibly take.
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

rewrite_build_files_for_ingress() {
  BUILD_DIR="/data/build/html"
  if [ ! -d "$BUILD_DIR" ]; then
    log_msg "[reconcile] Skipping ingress path rewrite (missing ${BUILD_DIR})"
    return 0
  fi

  rewritten_count=0

  find "$BUILD_DIR" -type f \( -name '*.html' -o -name '*.js' \) -print0 2>/dev/null | while IFS= read -r -d '' file; do
    tmp_file="${file}.sfs.tmp"
    if sed -E \
      -e 's#<script src="./js/ingress-api-shim.js"></script>##g' \
      -e 's#</head>#<script src="./js/ingress-api-shim.js"></script></head>#g' \
      -e "s#(href|src|action)=([\"'])/([^/][^\"']*)#\\1=\\2./\\3#g" \
      -e "s#(href|src|action)=([\"'])/((css|js|api|assets|files|gear-maintenance|img|images)[^\"']*)#\\1=\\2./\\3#g" \
      -e "s#(href|src|action)=([\"'])/([A-Za-z0-9._-]+\\.html([?][^\"']*)?)#\\1=\\2./\\3#g" \
      -e "s#(href|src|action)=([\"'])/([A-Za-z0-9._-]+([?][^\"']*)?)#\\1=\\2./\\3#g" \
      -e "s#(href|src|action)=([\"'])/(manifest\\.json[^\"']*)#\\1=\\2./\\3#g" \
      -e 's#"/(api|css|js|assets|files|gear-maintenance|img|images)/#"./\1/#g' \
      -e "s#'/(api|css|js|assets|files|gear-maintenance|img|images)/#'./\\1/#g" \
      -e 's#"/([A-Za-z0-9._-]+\.html([?][^"]*)?)"#"./\1"#g' \
      -e "s#'/([A-Za-z0-9._-]+\\.html([?][^']*)?)'#'./\\1'#g" \
      -e 's#"/([A-Za-z0-9._-]+([?][^"]*)?)"#"./\1"#g' \
      -e "s#'/([A-Za-z0-9._-]+([?][^']*)?)'#'./\\1'#g" \
      -e 's#"/manifest\.json"#"./manifest.json"#g' \
      -e "s#'/manifest\\.json'#'./manifest.json'#g" \
      "$file" > "$tmp_file"; then
      if ! cmp -s "$file" "$tmp_file"; then
        mv "$tmp_file" "$file"
        rewritten_count=$((rewritten_count + 1))
      else
        rm -f "$tmp_file"
      fi
    else
      rm -f "$tmp_file"
    fi
  done

  log_msg "[reconcile] Ingress path rewrite finished for build files"
}

rewrite_public_js_for_ingress() {
  APP_JS_FILE="/var/www/public/js/dist/app.min.js"
  if [ ! -f "$APP_JS_FILE" ]; then
    return 0
  fi

  tmp_file="${APP_JS_FILE}.sfs.tmp"
  # The SPA derives the page name from the route via
  # route.replace(basePath,'').replace(/^\/+/,'').replaceAll('/','-'). Under
  # ingress, appUrl is './' so routes are emitted as './heatmap', and the
  # leading './' survives the slash strip then becomes '.-heatmap' — so
  # `page === 'heatmap'` never matches and the dynamically-imported leaflet
  # chunk (heatmap map, photos, milestones) never loads. Strip an optional
  # leading './' too by widening /^\/+/ to /^\.?\/+/.
  if sed \
    -e 's#\\/api\\.\\/#\\/api\\/#g' \
    -e 's|/api\\./|/api/|g' \
    -e 's#replace(/^\\/+/,"")#replace(/^\\.?\\/+/,"")#g' \
    "$APP_JS_FILE" > "$tmp_file"; then
    if ! cmp -s "$APP_JS_FILE" "$tmp_file"; then
      mv "$tmp_file" "$APP_JS_FILE"
      log_msg "[reconcile] Ingress activity-route rewrite finished for public JS bundle"
    else
      rm -f "$tmp_file"
    fi
  else
    rm -f "$tmp_file"
  fi
}

prune_orphan_build_files() {
  # Remove stale files left in the served build dir. A successful build rewrites
  # every legitimate page (RunBuild dispatches all builders unconditionally and
  # each does buildHtmlStorage->write), so any file NOT touched by this build is
  # an orphan: a page for a deleted activity, a toggled-off section, or a file
  # placed manually. Upstream only ->write()s build-html and never prunes, so
  # orphans accumulate and Caddy keeps serving them (root /data/build/html).
  #
  # Prune by mtime against a marker stamped just before build start. MUST run
  # BEFORE the ingress rewrite: the rewrite sed-touches every *.html/*.js
  # (orphans included), which would bump their mtime and shield them from prune.
  marker="$1"
  BUILD_DIR="/data/build/html"
  if [ ! -d "$BUILD_DIR" ] || [ ! -f "$marker" ]; then
    return 0
  fi

  orphan_count="$(find "$BUILD_DIR" -type f ! -newer "$marker" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$orphan_count" -gt 0 ] 2>/dev/null; then
    find "$BUILD_DIR" -type f ! -newer "$marker" -delete 2>/dev/null || true
    find "$BUILD_DIR" -type d -empty -delete 2>/dev/null || true
    log_msg "[reconcile] Pruned ${orphan_count} orphan build file(s) from ${BUILD_DIR}"
  else
    log_msg "[reconcile] No orphan build files to prune"
  fi
}

ingress_rewrite_needed() {
  BUILD_DIR="/data/build/html"
  APP_JS_FILE="/var/www/public/js/dist/app.min.js"

  if [ ! -f "$INGRESS_REWRITE_MARKER_FILE" ]; then
    return 0
  fi

  if [ -f "$APP_JS_FILE" ] && [ "$APP_JS_FILE" -nt "$INGRESS_REWRITE_MARKER_FILE" ]; then
    return 0
  fi

  if [ -d "$BUILD_DIR" ] && find "$BUILD_DIR" -type f \( -name '*.html' -o -name '*.js' \) -newer "$INGRESS_REWRITE_MARKER_FILE" -print 2>/dev/null | grep -q .; then
    return 0
  fi

  return 1
}

mark_ingress_rewrite_complete() {
  touch "$INGRESS_REWRITE_MARKER_FILE"
}

if [ "$PHASE" = "rewrite" ]; then
  if ! ingress_rewrite_needed; then
    log_msg "[reconcile] Rewrite-only mode: skipping ingress rewrites (no changed files)"
    exit 0
  fi

  log_msg "[reconcile] Rewrite-only mode: applying ingress rewrites"
  rewrite_build_files_for_ingress
  rewrite_public_js_for_ingress
  mark_ingress_rewrite_complete
  exit 0
fi

if [ "$PHASE" = "config" ] || [ "$PHASE" = "full" ]; then
  # Record migration outcome so the (possibly separate, backgrounded) data phase
  # only imports/builds against a schema that migrated cleanly. Cleared first so
  # a stale marker from a prior boot can never green-light the data phase.
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
    warn_msg "Skipping import/build (database migrations did not complete cleanly)"
  else
    # Pick the startup command + phases for the configured mode.
    #
    # In "files" mode the mandatory v5 daemon is the sole importer (it runs
    # app:cron:run-file-import every 5 min). If this startup run ALSO imported, two
    # processes would work the shared watch dir; because the importer deletes each
    # file as it finishes, an overlap makes one process read a file the other has
    # already removed ("Unable to read ... watch/<file>: No such file"). So on
    # startup we only BUILD here (regenerate the dashboard from the existing
    # database on every restart) and leave all file importing to the daemon.
    #
    # In "stravaApi" mode there is no watch dir to contend for, so we still run a
    # full import+build on startup to give an immediate first import.
    if [ "$IMPORT_MODE" = "files" ]; then
      IMPORT_COMMAND="app:cron:run-file-import"
      IMPORT_FLAGS="--build"
    else
      IMPORT_COMMAND="app:cron:run-strava-import"
      IMPORT_FLAGS="--import --build"
    fi

    # Run the combined import+build at most once per startup. init runs the
    # config phase on boot; the backgrounded data phase runs this once. A fresh
    # boot always runs because the startup marker differs from the last stamp.
    # Steady-state data rebuilds run via the daemon's own import/build cron, not
    # this script.
    RUN_IMPORT_NOW="true"
    if [ -r "$STARTUP_MARKER_FILE" ]; then
      CURRENT_STARTUP_MARKER="$(tr -d '\n' < "$STARTUP_MARKER_FILE" || true)"
      LAST_IMPORT_MARKER=""
      if [ -r "$IMPORT_STARTUP_STAMP_FILE" ]; then
        LAST_IMPORT_MARKER="$(tr -d '\n' < "$IMPORT_STARTUP_STAMP_FILE" || true)"
      fi

      if [ -n "$CURRENT_STARTUP_MARKER" ] && [ "$CURRENT_STARTUP_MARKER" = "$LAST_IMPORT_MARKER" ]; then
        RUN_IMPORT_NOW="false"
        log_msg "[reconcile] Skipping ${IMPORT_COMMAND} (already attempted for this startup)"
      fi
    fi

    if [ "$RUN_IMPORT_NOW" = "true" ]; then
      # Record the startup this run covers so later reconciles this boot skip.
      if [ -r "$STARTUP_MARKER_FILE" ]; then
        tr -d '\n' < "$STARTUP_MARKER_FILE" > "$IMPORT_STARTUP_STAMP_FILE" || true
      fi

      # Stamp the marker just before build start, then wait 1s so every file the
      # build writes has a strictly newer mtime than the marker (find compares at
      # 1s granularity). prune_orphan_build_files keys off this boundary.
      log_msg "[reconcile] Running ${IMPORT_COMMAND} ${IMPORT_FLAGS}"
      touch "$BUILD_START_MARKER_FILE"
      sleep 1
      if run_console_command /tmp/sfs-import.log "$IMPORT_COMMAND" $IMPORT_FLAGS; then
        log_msg "[reconcile] ${IMPORT_COMMAND} finished"
        prune_orphan_build_files "$BUILD_START_MARKER_FILE"
        rewrite_build_files_for_ingress
        rewrite_public_js_for_ingress
        mark_ingress_rewrite_complete
      else
        RC=$?
        if [ "$RC" -eq 10 ]; then
          warn_msg "Skipped ${IMPORT_COMMAND} (mutex already acquired by another process)"
        else
          warn_msg "Failed to run ${IMPORT_COMMAND} (exit_code=${RC})"
        fi
        sed -n '1,40p' /tmp/sfs-import.log || true
        log_msg "[reconcile] Running ingress rewrites on existing files despite import/build failure"
        rewrite_build_files_for_ingress
        rewrite_public_js_for_ingress
        mark_ingress_rewrite_complete
      fi
    fi
  fi
fi
