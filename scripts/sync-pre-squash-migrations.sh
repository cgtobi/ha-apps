#!/usr/bin/env sh
# Maintains the vendored copy of the migrations from the upstream release right
# before the current migration squash. The add-on replays them for a database
# that skipped that release (see the add-on's sfs-migration-gate.sh).
#
# They are vendored rather than copied out of the upstream image at build time:
# the migrations are 160K, the image they live in is ~370MB, and pulling the
# whole thing is a cost every rebuild pays — including rebuilds on the user's own
# Home Assistant box. A squashed history is frozen by definition, so there is
# nothing to keep in sync until upstream squashes again.
#
# Usage:
#   sync-pre-squash-migrations.sh sync [addon] [image-tag]   refresh from an upstream image
#   sync-pre-squash-migrations.sh verify [addon]             check the vendored copy (no docker)
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEFAULT_ADDON="statistics_for_strava"

usage() {
  echo "Usage:"
  echo "  $0 sync [addon] [image-tag]"
  echo "  $0 verify [addon]"
  exit 2
}

MODE="${1:-}"
[ -n "$MODE" ] || usage
ADDON="${2:-$DEFAULT_ADDON}"
ADDON_DIR="${ROOT_DIR}/${ADDON}"
STASH_DIR="${ADDON_DIR}/pre-squash-migrations"
SOURCE_FILE="${STASH_DIR}/.source"
SUMS_FILE="${STASH_DIR}/SHA256SUMS"
DOCKERFILE="${ADDON_DIR}/Dockerfile"

[ -f "${ADDON_DIR}/config.yaml" ] || { echo "ERROR: unknown add-on '${ADDON}'" >&2; exit 1; }

dockerfile_pre_squash_image() {
  sed -n 's/^ARG PRE_SQUASH_FROM=//p' "$DOCKERFILE" | head -n1
}

write_sums() {
  # Only the migrations themselves: the two metadata files cannot list their own
  # digests, and the build-time check verifies exactly this list.
  (cd "$STASH_DIR" && find . -maxdepth 1 -name 'Version*.php' | sed 's|^\./||' | sort | xargs sha256sum > SHA256SUMS)
}

case "$MODE" in
  sync)
    IMAGE="${3:-$(dockerfile_pre_squash_image)}"
    [ -n "$IMAGE" ] || { echo "ERROR: no image tag given and none in ${DOCKERFILE}" >&2; exit 1; }

    echo "Syncing ${ADDON} pre-squash migrations from ${IMAGE}"
    # The directory is replaced wholesale so a migration upstream dropped does not
    # survive the sync — but README.md is ours, not upstream's, so it is carried over.
    readme_tmp=""
    if [ -f "${STASH_DIR}/README.md" ]; then
      readme_tmp="$(mktemp)"
      cp "${STASH_DIR}/README.md" "$readme_tmp"
    fi
    rm -rf "$STASH_DIR"
    mkdir -p "$STASH_DIR"
    if [ -n "$readme_tmp" ]; then
      mv "$readme_tmp" "${STASH_DIR}/README.md"
    fi
    cid="$(docker create "$IMAGE")"
    # shellcheck disable=SC2064
    trap "docker rm '$cid' >/dev/null 2>&1 || true" EXIT INT TERM
    docker cp "${cid}:/var/www/migrations/." "$STASH_DIR/" >/dev/null

    {
      printf 'image=%s\n' "$IMAGE"
      printf 'synced_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$SOURCE_FILE"
    write_sums

    echo "OK: ${ADDON}: vendored $(find "$STASH_DIR" -maxdepth 1 -name 'Version*.php' | wc -l | tr -d ' ') migrations from ${IMAGE}"
    echo "Remember to point ARG PRE_SQUASH_FROM at ${IMAGE} and ARG PRE_SQUASH_ADDON_VERSION at the add-on release that shipped it."
    ;;
  verify)
    fail=0
    [ -d "$STASH_DIR" ] || { echo "ERROR: ${ADDON}: missing ${STASH_DIR}" >&2; exit 1; }
    [ -f "$SOURCE_FILE" ] || { echo "ERROR: ${ADDON}: missing ${SOURCE_FILE}" >&2; exit 1; }
    [ -f "$SUMS_FILE" ] || { echo "ERROR: ${ADDON}: missing ${SUMS_FILE}" >&2; exit 1; }

    recorded="$(sed -n 's/^image=//p' "$SOURCE_FILE" | head -n1)"
    declared="$(dockerfile_pre_squash_image)"
    if [ "$recorded" != "$declared" ]; then
      echo "Mismatch: ${ADDON}: vendored migrations came from '${recorded}', Dockerfile declares '${declared}'" >&2
      fail=1
    fi

    if ! (cd "$STASH_DIR" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1 || sha256sum -c SHA256SUMS >/dev/null 2>&1); then
      echo "Mismatch: ${ADDON}: vendored migrations do not match SHA256SUMS (edited by hand, or an incomplete sync)" >&2
      fail=1
    fi

    [ "$fail" -eq 0 ] || exit 1
    echo "OK: ${ADDON}: vendored pre-squash migrations match ${recorded}"
    ;;
  *)
    usage
    ;;
esac
