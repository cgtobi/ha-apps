#!/bin/sh
# Upgrade gate for upstream's squashed migration history.
#
# v5.4.0 squashed 34 migrations into one. Its MigrationSquashHandler refuses to
# run (MigrationsOutdated) unless the database is either already on the squashed
# migration or on the very last migration before it — i.e. unless the user came
# through v5.3.3. Home Assistant offers no way to force an update through an
# intermediate add-on version: an install sitting on an old release updates
# straight to the newest one in the repository. So the stepping stone has to
# happen inside the image.
#
# Nothing here is about data safety — upstream throws before touching the schema.
# It is about what the user sees: without this, the jump surfaces as a WARN ten
# lines deep in the log, the add-on starts anyway on a stale schema, and every
# page is broken with no hint why.
#
# Three outcomes:
#   ok          - nothing to do, boot continues (fresh install included)
#   remediable  - run the stashed pre-squash migrations up to the baseline
#                 upstream wants, then boot continues normally
#   blocked     - the database predates even the stash; stop before the app
#                 starts and let start.sh serve the instructions instead
#
# Exit codes: 0 = continue boot, 3 = blocked.
set -eu

GUARD_ENV="/usr/local/share/sfs/squash-guard.env"
STASH_DIR="/usr/local/share/sfs/pre-squash-migrations"
MIGRATIONS_DIR="/var/www/migrations"
DB_FILE="/data/storage/database/dreeve.db"
BLOCKED_MARKER="/data/runtime/upgrade-blocked"

timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

log() {
  echo "$(timestamp) [migration-gate] $*"
}

warn() {
  echo "$(timestamp) [migration-gate] WARN: $*"
}

# A broken guard must not brick a working add-on: upstream's own handler still
# refuses to migrate a database that is too old, so the worst case without us is
# the pre-existing behaviour.
if [ ! -r "$GUARD_ENV" ]; then
  warn "Squash guard data missing (${GUARD_ENV}); skipping the upgrade-path check"
  exit 0
fi

# shellcheck disable=SC1090
. "$GUARD_ENV"

read_state() {
  php /usr/local/bin/sfs-migration-state.php \
    "$SFS_SQUASHED_MIGRATION_ID" \
    "$SFS_LAST_MIGRATION_BEFORE_SQUASH_ID" \
    "$STASH_DIR" \
    "$DB_FILE" 2>&1 | tail -n1
}

block() {
  {
    printf 'blocked_at=%s\n' "$(timestamp)"
    printf 'required_version=%s\n' "$SFS_PRE_SQUASH_VERSION"
    printf 'required_addon_version=%s\n' "$SFS_PRE_SQUASH_ADDON_VERSION"
  } > "$BLOCKED_MARKER"

  warn "This database has not been through Dreeve ${SFS_PRE_SQUASH_VERSION}, and the add-on cannot bring it there on its own."
  warn "Upstream squashed its migration history; ${SFS_PRE_SQUASH_VERSION} is the last release that can migrate this database forward."
  warn "What to do: restore the Home Assistant backup of add-on version ${SFS_PRE_SQUASH_ADDON_VERSION} (or reinstall it), start it once so the migrations run, then update again."
  warn "The database has not been modified. The add-on stays up and serves these instructions instead of the app."
  exit 3
}

# The stashed migrations are only copied in for the length of the catch-up run.
# Leaving them behind would make every later boot's doctrine:migrations:status
# list 34 extra "available" migrations that the squashed image does not ship.
COPIED_LIST=""
cleanup_stash() {
  [ -n "$COPIED_LIST" ] || return 0
  for copied in $COPIED_LIST; do
    rm -f "${MIGRATIONS_DIR}/${copied}"
  done
  COPIED_LIST=""
}

remediate() {
  if [ ! -d "$MIGRATIONS_DIR" ]; then
    warn "Upstream migrations directory missing: ${MIGRATIONS_DIR}"
    block
  fi

  log "Database is behind the migration squash; running the stashed ${SFS_PRE_SQUASH_VERSION} migrations first"

  trap 'cleanup_stash' EXIT INT TERM
  for stashed in "$STASH_DIR"/Version*.php; do
    [ -f "$stashed" ] || continue
    name="$(basename "$stashed")"
    if [ ! -e "${MIGRATIONS_DIR}/${name}" ]; then
      cp "$stashed" "${MIGRATIONS_DIR}/${name}"
      COPIED_LIST="${COPIED_LIST} ${name}"
    fi
  done

  # Migrate to the exact baseline upstream's handler looks for, not to "latest":
  # the squashed migration is also in the directory and would try to create the
  # schema from scratch on top of the live one. Everything after this point is
  # the normal app:db:migrate path, which marks the squash executed.
  if (cd /var/www && php bin/console doctrine:migrations:migrate \
        "DoctrineMigrations\\${SFS_LAST_MIGRATION_BEFORE_SQUASH_ID}" \
        --no-interaction --allow-no-migration >/tmp/sfs-presquash-migrate.log 2>&1); then
    log "Pre-squash migrations finished"
  else
    warn "Pre-squash migrations failed:"
    sed -n '1,40p' /tmp/sfs-presquash-migrate.log || true
  fi

  cleanup_stash
  trap - EXIT INT TERM

  # Verify rather than assume: a partially applied catch-up leaves the database
  # in a state upstream will still refuse, and booting on into app:db:migrate
  # would bury that under the generic migration warning.
  if [ "$(read_state)" != "ok" ]; then
    warn "The database is still behind after the catch-up run"
    block
  fi

  log "Database is now at the baseline upstream expects; continuing"
}

STATE="$(read_state)"

case "$STATE" in
  ok|fresh)
    ;;
  remediable)
    remediate
    ;;
  blocked)
    block
    ;;
  *)
    warn "Could not determine the database migration state (${STATE}); continuing and letting upstream decide"
    ;;
esac

# A previous boot may have left the marker behind; the state above says the
# database is fine now, so the app must not come up in blocked mode again.
rm -f "$BLOCKED_MARKER"
exit 0
