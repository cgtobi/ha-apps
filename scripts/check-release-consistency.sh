#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

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

# Every directory holding a config.yaml is an add-on. Discovered rather than listed, so a new
# connector add-on needs no change here.
addon_dirs() {
  for candidate in "${ROOT_DIR}"/*/config.yaml; do
    [ -f "$candidate" ] || continue
    basename "$(dirname "$candidate")"
  done
}

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
  fail=0
  for addon in $(addon_dirs); do
    config_file="${addon}/config.yaml"
    changelog_file="${addon}/CHANGELOG.md"

    if [ ! -f "${ROOT_DIR}/${config_file}" ] || [ ! -f "${ROOT_DIR}/${changelog_file}" ]; then
      echo "ERROR: ${addon}: missing config.yaml or CHANGELOG.md" >&2
      fail=1
      continue
    fi

    config_version="$(extract_config_version < "${ROOT_DIR}/${config_file}")"
    changelog_version="$(extract_top_changelog_version < "${ROOT_DIR}/${changelog_file}")"

    if [ -z "$config_version" ] || [ -z "$changelog_version" ]; then
      echo "ERROR: ${addon}: could not parse versions" >&2
      fail=1
      continue
    fi

    if [ "$config_version" != "$changelog_version" ]; then
      echo "ERROR: ${addon}: version mismatch" >&2
      echo "  ${config_file}:   ${config_version}" >&2
      echo "  ${changelog_file}: ${changelog_version}" >&2
      fail=1
      continue
    fi

    if [ "$quiet" != "1" ]; then
      echo "OK: ${addon}: release version is consistent (${config_version})"
    fi
  done

  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

if ! git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: not in a git repository" >&2
  exit 1
fi

fail=0
for addon in $(addon_dirs); do
  config_file="${addon}/config.yaml"
  changelog_file="${addon}/CHANGELOG.md"

  staged_in_addon="$(git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMRD -- "$addon" || true)"
  [ -n "$staged_in_addon" ] || continue

  staged_config_version="$(git -C "$ROOT_DIR" show ":${config_file}" 2>/dev/null | extract_config_version || true)"
  staged_changelog_version="$(git -C "$ROOT_DIR" show ":${changelog_file}" 2>/dev/null | extract_top_changelog_version || true)"

  if [ -z "$staged_config_version" ] || [ -z "$staged_changelog_version" ]; then
    echo "ERROR: ${addon}: could not read staged versions" >&2
    fail=1
    continue
  fi

  if [ "$staged_config_version" != "$staged_changelog_version" ]; then
    echo "ERROR: ${addon}: staged version mismatch" >&2
    echo "  ${config_file}:   ${staged_config_version}" >&2
    echo "  ${changelog_file}: ${staged_changelog_version}" >&2
    fail=1
    continue
  fi

  if [ "$require_bump" = "1" ]; then
    head_config_version="$(git -C "$ROOT_DIR" show "HEAD:${config_file}" 2>/dev/null | extract_config_version || true)"
    if [ -n "$head_config_version" ] && ! semver_gt "$staged_config_version" "$head_config_version"; then
      echo "ERROR: ${addon}: ${config_file} version must be greater than HEAD" >&2
      echo "  staged: ${staged_config_version}" >&2
      echo "  head:   ${head_config_version}" >&2
      fail=1
      continue
    fi
  fi

  if [ "$quiet" != "1" ]; then
    echo "OK: ${addon}: staged release version is consistent (${staged_config_version})"
  fi
done

[ "$fail" -eq 0 ] || exit 1
