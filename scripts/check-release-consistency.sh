#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIG_FILE="statistics_for_strava/config.yaml"
CHANGELOG_FILE="statistics_for_strava/CHANGELOG.md"

mode="working"
require_bump="0"
quiet="0"

for arg in "$@"; do
  case "$arg" in
    --staged) mode="staged" ;;
    --require-bump) require_bump="1" ;;
    --quiet) quiet="1" ;;
    *)
      echo "Usage: $0 [--staged] [--require-bump] [--quiet]" >&2
      exit 2
      ;;
  esac
done

extract_config_version() {
  sed -n 's/^version:[[:space:]]*"\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' | head -n1
}

extract_top_changelog_version() {
  awk '
    /^##[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+([[:space:]].*)?$/ {
      print $2
      exit
    }
  '
}

semver_gt() {
  a="$1"
  b="$2"
  awk -v a="$a" -v b="$b" '
    function parse(v, out, t) {
      split(v, t, ".")
      out[1] = t[1] + 0
      out[2] = t[2] + 0
      out[3] = t[3] + 0
    }
    BEGIN {
      parse(a, A)
      parse(b, B)
      if (A[1] > B[1]) exit 0
      if (A[1] < B[1]) exit 1
      if (A[2] > B[2]) exit 0
      if (A[2] < B[2]) exit 1
      if (A[3] > B[3]) exit 0
      exit 1
    }
  '
}

if [ "$mode" = "working" ]; then
  if [ ! -f "${ROOT_DIR}/${CONFIG_FILE}" ] || [ ! -f "${ROOT_DIR}/${CHANGELOG_FILE}" ]; then
    echo "ERROR: missing ${CONFIG_FILE} or ${CHANGELOG_FILE}" >&2
    exit 1
  fi

  config_version="$(extract_config_version < "${ROOT_DIR}/${CONFIG_FILE}")"
  if [ -z "$config_version" ]; then
    echo "ERROR: could not parse add-on version from ${CONFIG_FILE}" >&2
    exit 1
  fi

  changelog_version="$(extract_top_changelog_version < "${ROOT_DIR}/${CHANGELOG_FILE}")"
  if [ -z "$changelog_version" ]; then
    echo "ERROR: could not parse top release version from ${CHANGELOG_FILE}" >&2
    exit 1
  fi

  if [ "$config_version" != "$changelog_version" ]; then
    echo "ERROR: version mismatch detected" >&2
    echo "  ${CONFIG_FILE}:   ${config_version}" >&2
    echo "  ${CHANGELOG_FILE}: ${changelog_version}" >&2
    exit 1
  fi

  if [ "$quiet" != "1" ]; then
    echo "OK: release version is consistent (${config_version})"
  fi
  exit 0
fi

if ! git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: not in a git repository" >&2
  exit 1
fi

staged_config_version="$(git -C "$ROOT_DIR" show ":${CONFIG_FILE}" 2>/dev/null | extract_config_version || true)"
if [ -z "$staged_config_version" ]; then
  echo "ERROR: could not read staged add-on version from ${CONFIG_FILE}" >&2
  exit 1
fi

staged_changelog_version="$(git -C "$ROOT_DIR" show ":${CHANGELOG_FILE}" 2>/dev/null | extract_top_changelog_version || true)"
if [ -z "$staged_changelog_version" ]; then
  echo "ERROR: could not read staged top release version from ${CHANGELOG_FILE}" >&2
  exit 1
fi

if [ "$staged_config_version" != "$staged_changelog_version" ]; then
  echo "ERROR: staged version mismatch detected" >&2
  echo "  ${CONFIG_FILE}:   ${staged_config_version}" >&2
  echo "  ${CHANGELOG_FILE}: ${staged_changelog_version}" >&2
  exit 1
fi

if [ "$require_bump" = "1" ]; then
  head_config_version="$(git -C "$ROOT_DIR" show "HEAD:${CONFIG_FILE}" 2>/dev/null | extract_config_version || true)"
  if [ -n "$head_config_version" ] && ! semver_gt "$staged_config_version" "$head_config_version"; then
    echo "ERROR: ${CONFIG_FILE} version must be greater than HEAD" >&2
    echo "  staged: ${staged_config_version}" >&2
    echo "  head:   ${head_config_version}" >&2
    exit 1
  fi
fi

if [ "$quiet" != "1" ]; then
  echo "OK: staged release version is consistent (${staged_config_version})"
fi
