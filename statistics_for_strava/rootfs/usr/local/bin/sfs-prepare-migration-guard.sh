#!/bin/sh
# Build-time half of the migration-squash gate (runtime half: sfs-migration-gate.sh).
#
# Derives the two migration ids the gate compares against from the image itself
# instead of hardcoding them here. Upstream squashes every few releases and
# rewrites both constants when it does; a hardcoded pair would keep matching the
# previous squash and silently wave through exactly the upgrade it exists to
# catch. Everything this script cannot derive, it fails the build over.
#
# Usage: sfs-prepare-migration-guard.sh <pre-squash-image-ref> <pre-squash-addon-version>
set -eu

HANDLER="/var/www/src/Infrastructure/Doctrine/Migrations/MigrationSquashHandler.php"
MIGRATIONS_DIR="/var/www/migrations"
STASH_DIR="/usr/local/share/sfs/pre-squash-migrations"
SHARE_DIR="/usr/local/share/sfs"
TEMPLATE="${SHARE_DIR}/upgrade-blocked.html.in"
OUT_ENV="${SHARE_DIR}/squash-guard.env"
OUT_DIR="${SHARE_DIR}/blocked"

PRE_SQUASH_IMAGE="${1:-}"
PRE_SQUASH_VERSION="${PRE_SQUASH_IMAGE##*:}"
PRE_SQUASH_ADDON_VERSION="${2:-}"

fail() {
  echo "sfs-prepare-migration-guard: $*" >&2
  exit 1
}

[ -n "$PRE_SQUASH_IMAGE" ] || fail "missing pre-squash image reference argument"
[ -n "$PRE_SQUASH_ADDON_VERSION" ] || fail "missing pre-squash add-on version argument"
[ -f "$HANDLER" ] || fail "upstream no longer ships MigrationSquashHandler.php (it moved, or the squash mechanism changed — rework the gate)"

# --- the two ids the gate compares the database against --------------------
extract_id() {
  const_name="$1"
  line="$(grep -F "const string ${const_name}" "$HANDLER" || true)"
  [ -n "$line" ] || fail "${const_name} not found in MigrationSquashHandler.php"
  case "$line" in
    *DoctrineMigrations*) ;;
    *) fail "${const_name} no longer names a DoctrineMigrations class: ${line}" ;;
  esac
  id="$(printf '%s\n' "$line" | grep -oE 'Version[0-9]{6,}' | head -n1)"
  [ -n "$id" ] || fail "could not read a migration id out of: ${line}"
  printf '%s\n' "$id"
}

SQUASH_ID="$(extract_id SQUASHED_MIGRATION)"
LAST_ID="$(extract_id LAST_MIGRATION_BEFORE_SQUASH)"

[ -f "${MIGRATIONS_DIR}/${SQUASH_ID}.php" ] \
  || fail "the image's migrations directory has no ${SQUASH_ID}.php, so ${SQUASH_ID} is not this image's squash — the handler and the shipped migrations disagree"

# --- the stash the gate closes the gap with --------------------------------
#
# It must be the migrations of the release immediately before the squash: the
# gate replays them up to LAST_MIGRATION_BEFORE_SQUASH, which is exactly the
# state upstream's handler demands. A stash from any other release cannot reach
# that baseline, which is what the next check catches — and it catches it on the
# first build after upstream squashes again, which is when PRE_SQUASH_FROM in
# the Dockerfile needs bumping.
[ -d "$STASH_DIR" ] || fail "pre-squash migration stash missing at ${STASH_DIR}"

# The stash is vendored in the repository rather than copied out of the upstream
# image at build time (a second build stage would pull ~370MB for 160K of files,
# on every rebuild, the user's own box included). What that trades away is
# docker's guarantee that the files came from where the Dockerfile says, so the
# sync script records the image and the digests, and both are checked here.
SOURCE_FILE="${STASH_DIR}/.source"
[ -f "$SOURCE_FILE" ] || fail "vendored stash has no .source record — refresh it with scripts/sync-pre-squash-migrations.sh"
RECORDED_IMAGE="$(sed -n 's/^image=//p' "$SOURCE_FILE" | head -n1)"
[ "$RECORDED_IMAGE" = "$PRE_SQUASH_IMAGE" ] \
  || fail "the vendored migrations came from '${RECORDED_IMAGE}' but PRE_SQUASH_FROM says '${PRE_SQUASH_IMAGE}' — re-sync the stash or fix the arg"

[ -f "${STASH_DIR}/SHA256SUMS" ] || fail "vendored stash has no SHA256SUMS — refresh it with scripts/sync-pre-squash-migrations.sh"
(cd "$STASH_DIR" && sha256sum -c SHA256SUMS >/dev/null) \
  || fail "the vendored migrations do not match their recorded digests (edited by hand, or an incomplete sync)"

[ -f "${STASH_DIR}/${LAST_ID}.php" ] \
  || fail "the pre-squash stash (${PRE_SQUASH_VERSION}) has no ${LAST_ID}.php — upstream squashed again, so PRE_SQUASH_FROM must point at the release before the new squash"

[ ! -f "${STASH_DIR}/${SQUASH_ID}.php" ] \
  || fail "the pre-squash stash (${PRE_SQUASH_VERSION}) already contains the squashed migration ${SQUASH_ID} — PRE_SQUASH_FROM points at a release at or after the squash"

# The stashed migrations run inside THIS image, so every App class they import
# has to still exist here. Same failure mode, and same check, as the overridden
# files in sfs-verify-overrides.sh: a `use` line naming a moved class is a fatal
# the moment that migration is replayed, halfway through the catch-up.
unknown=""
for migration in "$STASH_DIR"/Version*.php; do
  [ -f "$migration" ] || continue
  for class in $(sed -n 's/^use \(App\\[A-Za-z0-9_\\]*\);$/\1/p' "$migration"); do
    class_rel="$(printf '%s\n' "$class" | tr '\\' '/')"
    class_rel="${class_rel#App/}"
    [ -f "/var/www/src/${class_rel}.php" ] || unknown="${unknown}$(basename "$migration") imports ${class}; "
  done
done
[ -z "$unknown" ] \
  || fail "stashed pre-squash migrations import classes this image does not have: ${unknown}(they would fatal mid-catch-up)"

# --- what the runtime half reads -------------------------------------------
{
  printf '# Generated at build time by sfs-prepare-migration-guard.sh. Do not edit.\n'
  printf 'SFS_SQUASHED_MIGRATION_ID=%s\n' "$SQUASH_ID"
  printf 'SFS_LAST_MIGRATION_BEFORE_SQUASH_ID=%s\n' "$LAST_ID"
  printf 'SFS_PRE_SQUASH_VERSION=%s\n' "$PRE_SQUASH_VERSION"
  printf 'SFS_PRE_SQUASH_ADDON_VERSION=%s\n' "$PRE_SQUASH_ADDON_VERSION"
} > "$OUT_ENV"

[ -f "$TEMPLATE" ] || fail "blocked-page template missing at ${TEMPLATE}"
mkdir -p "$OUT_DIR"
sed -e "s/@@PRE_SQUASH_VERSION@@/${PRE_SQUASH_VERSION}/g" \
    -e "s/@@PRE_SQUASH_ADDON_VERSION@@/${PRE_SQUASH_ADDON_VERSION}/g" \
    "$TEMPLATE" > "${OUT_DIR}/index.html"
rm -f "$TEMPLATE"

echo "sfs-prepare-migration-guard: ok (squash=${SQUASH_ID}, baseline=${LAST_ID}, stash=${PRE_SQUASH_VERSION})"
