#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"
CONFIG_DIR="/data/config/app"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
CHALLENGE_HISTORY_FILE="/data/storage/files/strava-challenge-history.html"
LOCK_DIR="/tmp/sfs-config-reconcile.lock"
RUNTIME_DIR="/data/runtime"
STATUS_FILE="${RUNTIME_DIR}/reconcile.status"
STARTUP_MARKER_FILE="${RUNTIME_DIR}/health.startup"
IMPORT_STARTUP_STAMP_FILE="${RUNTIME_DIR}/reconcile.import.startup"
BUILD_STARTUP_STAMP_FILE="${RUNTIME_DIR}/reconcile.build.startup"
BUILD_START_MARKER_FILE="${RUNTIME_DIR}/reconcile.build.start"
BUILD_INDEX_FILE="/data/build/html/index.html"
INGRESS_REWRITE_MARKER_FILE="${RUNTIME_DIR}/ingress-rewrite.last"

timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

log_msg() {
  printf '%s %s\n' "$(timestamp_utc)" "$*"
}

warn_msg() {
  log_msg "WARN: $*"
}

fatal_msg() {
  log_msg "FATAL: $*"
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

APP_CONFIG_YAML="$(jq -r '.app_config_yaml // ""' "$OPTIONS_FILE")"
RECONCILE_RUN_IMPORT="$(jq -r '.reconcile_run_import // true' "$OPTIONS_FILE")"
STRAVA_CLIENT_ID="$(jq -r '.strava_client_id // ""' "$OPTIONS_FILE")"
STRAVA_CLIENT_SECRET="$(jq -r '.strava_client_secret // ""' "$OPTIONS_FILE")"
STRAVA_REFRESH_TOKEN="$(jq -r '.strava_refresh_token // ""' "$OPTIONS_FILE")"
TZ_VALUE="$(jq -r '.tz // ""' "$OPTIONS_FILE")"
if [ -z "$APP_CONFIG_YAML" ]; then
  exit 0
fi

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

if [ "${SFS_RECONCILE_REWRITE_ONLY:-0}" = "1" ]; then
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

CANDIDATE_CONFIG="${CONFIG_FILE}.candidate"
if ! php /usr/local/share/sfs/render-app-config.php "$OPTIONS_FILE" "$CANDIDATE_CONFIG" >/tmp/sfs-config-render.log 2>&1; then
  fatal_msg "Could not render app config from add-on options"
  sed -n '1,5p' /tmp/sfs-config-render.log || true
  rm -f "$CANDIDATE_CONFIG"
  exit 1
fi

if ! php /usr/local/share/sfs/validate-app-config.php "$CANDIDATE_CONFIG" >/tmp/sfs-config-validate.log 2>&1; then
  fatal_msg "Invalid app_config_yaml in add-on options"
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
  log_msg "[reconcile] Updated ${CHALLENGE_HISTORY_FILE} from add-on options"
fi

if [ -f /var/www/bin/console ]; then
  log_msg "[reconcile] Running doctrine migrations"
  if ! (cd /var/www && php bin/console doctrine:migrations:migrate --no-interaction >/tmp/sfs-migrate.log 2>&1); then
    warn_msg "Failed to run doctrine migrations during config reconcile"
    sed -n '1,10p' /tmp/sfs-migrate.log || true
  else
    log_msg "[reconcile] Doctrine migrations finished"
    IMPORT_COMMAND="app:strava:import-data"

    RUN_IMPORT_NOW="true"
    if [ "$RECONCILE_RUN_IMPORT" != "true" ]; then
      RUN_IMPORT_NOW="false"
      log_msg "[reconcile] Skipping import before build-files (reconcile_run_import=false)"
    elif [ -r "$STARTUP_MARKER_FILE" ]; then
      CURRENT_STARTUP_MARKER="$(tr -d '\n' < "$STARTUP_MARKER_FILE" || true)"
      LAST_IMPORT_MARKER=""
      if [ -r "$IMPORT_STARTUP_STAMP_FILE" ]; then
        LAST_IMPORT_MARKER="$(tr -d '\n' < "$IMPORT_STARTUP_STAMP_FILE" || true)"
      fi

      if [ -n "$CURRENT_STARTUP_MARKER" ] && [ "$CURRENT_STARTUP_MARKER" = "$LAST_IMPORT_MARKER" ]; then
        RUN_IMPORT_NOW="false"
        log_msg "[reconcile] Skipping import before build-files (already attempted for this startup)"
      fi
    fi

    if [ "$RUN_IMPORT_NOW" = "true" ]; then
      if [ -r "$STARTUP_MARKER_FILE" ]; then
        tr -d '\n' < "$STARTUP_MARKER_FILE" > "$IMPORT_STARTUP_STAMP_FILE" || true
      fi
    fi

    if [ "$RUN_IMPORT_NOW" = "true" ]; then
      log_msg "[reconcile] Running ${IMPORT_COMMAND}"
      if run_console_command /tmp/sfs-import.log "$IMPORT_COMMAND"; then
        log_msg "[reconcile] ${IMPORT_COMMAND} finished"
      else
        IMPORT_RC=$?
        if [ "$IMPORT_RC" -eq 10 ]; then
          warn_msg "Skipped ${IMPORT_COMMAND} during config reconcile (mutex already acquired by another process)"
        else
          warn_msg "Failed to run ${IMPORT_COMMAND} during config reconcile (exit_code=${IMPORT_RC})"
        fi
        sed -n '1,20p' /tmp/sfs-import.log || true
      fi
    else
      :
    fi

    # Build at most once per startup unless the config changed. init, web and
    # daemon each call reconcile on boot, and the daemon restarts on crash;
    # without this gate every one triggers a full rebuild of all activity HTML.
    # A real config change (CHANGED=true) or a missing build index always
    # rebuilds. Steady-state data rebuilds run via the daemon's own
    # importDataAndBuildApp cron, not this script.
    SHOULD_BUILD="true"
    if [ "$CHANGED" != "true" ] && [ -f "$BUILD_INDEX_FILE" ]; then
      if [ -r "$STARTUP_MARKER_FILE" ]; then
        CURRENT_STARTUP_MARKER="$(tr -d '\n' < "$STARTUP_MARKER_FILE" || true)"
        LAST_BUILD_MARKER=""
        if [ -r "$BUILD_STARTUP_STAMP_FILE" ]; then
          LAST_BUILD_MARKER="$(tr -d '\n' < "$BUILD_STARTUP_STAMP_FILE" || true)"
        fi
        if [ -n "$CURRENT_STARTUP_MARKER" ] && [ "$CURRENT_STARTUP_MARKER" = "$LAST_BUILD_MARKER" ]; then
          SHOULD_BUILD="false"
        fi
      fi
    fi

    if [ "$SHOULD_BUILD" != "true" ]; then
      log_msg "[reconcile] Skipping app:strava:build-files (already built this startup, config unchanged)"
    else
    # Stamp the marker just before build start, then wait 1s so every file the
    # build writes has a strictly newer mtime than the marker (find compares at
    # 1s granularity). prune_orphan_build_files keys off this boundary.
    touch "$BUILD_START_MARKER_FILE"
    sleep 1
    log_msg "[reconcile] Running app:strava:build-files"
    if run_console_command /tmp/sfs-build-files.log app:strava:build-files; then
      log_msg "[reconcile] app:strava:build-files finished"
      # Record the startup this build covers so later reconciles this boot skip.
      # Only on success, so a failed build is retried by the next reconcile.
      if [ -r "$STARTUP_MARKER_FILE" ]; then
        tr -d '\n' < "$STARTUP_MARKER_FILE" > "$BUILD_STARTUP_STAMP_FILE" || true
      fi
      prune_orphan_build_files "$BUILD_START_MARKER_FILE"
      rewrite_build_files_for_ingress
      rewrite_public_js_for_ingress
      mark_ingress_rewrite_complete
    else
      BUILD_RC=$?
      if [ "$BUILD_RC" -eq 10 ]; then
        warn_msg "Skipped app:strava:build-files during config reconcile (mutex already acquired by another process)"
      else
        warn_msg "Failed to run app:strava:build-files during config reconcile (exit_code=${BUILD_RC})"
      fi
      cp /tmp/sfs-build-files.log /data/runtime/sfs-build-files.last.log 2>/dev/null || true
      printf 'failed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /data/runtime/sfs-build-files.last.meta 2>/dev/null || true
      printf 'exit_code=%s\n' "$BUILD_RC" >> /data/runtime/sfs-build-files.last.meta 2>/dev/null || true
      log_msg "[reconcile] build-files log (first 40 lines)"
      sed -n '1,40p' /tmp/sfs-build-files.log || true
      log_msg "[reconcile] build-files log (last 40 lines)"
      tail -n 40 /tmp/sfs-build-files.log || true
      log_msg "[reconcile] Full build-files log saved to /data/runtime/sfs-build-files.last.log"
      log_msg "[reconcile] Running ingress rewrites on existing files despite build-files failure"
      rewrite_build_files_for_ingress
      rewrite_public_js_for_ingress
      mark_ingress_rewrite_complete
    fi
    fi
  fi
fi

{
  printf 'updated_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'changed=%s\n' "$CHANGED"
  printf 'config_sha256=%s\n' "$CANDIDATE_SHA"
} > "$STATUS_FILE"
