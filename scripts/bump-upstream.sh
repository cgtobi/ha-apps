#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ADDON_DIR="${ROOT_DIR}/statistics_for_strava"
VERSION_FILE="${ADDON_DIR}/.upstream-version"
DOCKERFILE="${ADDON_DIR}/Dockerfile"
CONFIG_YAML="${ADDON_DIR}/config.yaml"
CHANGELOG="${ADDON_DIR}/CHANGELOG.md"
IMAGE_REPO="ghcr.io/robiningelbrecht/statistics-for-strava"
UPSTREAM_GIT_URL="https://github.com/robiningelbrecht/statistics-for-strava.git"
CHECK_SCRIPT="${ROOT_DIR}/scripts/check-release-consistency.sh"

usage() {
  echo "Usage:"
  echo "  $0 bump [upstream-version-tag]"
  echo "  $0 check"
  echo "  $0"
  echo "Examples:"
  echo "  $0 bump v4.7.5"
  echo "  $0 bump"
  echo "  $0 check"
  echo "  $0"
}

get_config_version() {
  sed -n 's/^version:[[:space:]]*"\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' "$CONFIG_YAML" | head -n1
}

next_patch_version() {
  current="$1"
  IFS=. read -r major minor patch <<EOFV
$current
EOFV
  if [ -z "${major:-}" ] || [ -z "${minor:-}" ] || [ -z "${patch:-}" ]; then
    echo "ERROR: invalid semantic version '${current}'" >&2
    exit 1
  fi
  patch=$((patch + 1))
  echo "${major}.${minor}.${patch}"
}

set_config_version() {
  new_version="$1"
  tmp_config="$(mktemp)"
  awk -v new_version="$new_version" '
    BEGIN { updated = 0 }
    /^version:[[:space:]]*"/ && updated == 0 {
      print "version: \"" new_version "\""
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print "ERROR: version line not found in config.yaml" > "/dev/stderr"
        exit 5
      }
    }
  ' "$CONFIG_YAML" > "$tmp_config"
  mv "$tmp_config" "$CONFIG_YAML"
}

prepend_changelog_release() {
  addon_version="$1"
  upstream_version="$2"
  tmp_changelog="$(mktemp)"
  awk -v addon_version="$addon_version" -v upstream_version="$upstream_version" '
    BEGIN {
      inserted = 0
      skip_first_blank_after_header = 0
      new_line = "- feat: bump Statistics for Strava to " upstream_version " [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)"
    }
    /^# Changelog[[:space:]]*$/ && !inserted {
      print
      print ""
      print "## " addon_version
      print ""
      print new_line
      print ""
      inserted = 1
      skip_first_blank_after_header = 1
      next
    }
    {
      if (skip_first_blank_after_header && $0 == "") {
        skip_first_blank_after_header = 0
        next
      }
      skip_first_blank_after_header = 0
      print
    }
    END {
      if (!inserted) {
        print "ERROR: could not locate changelog header in CHANGELOG.md" > "/dev/stderr"
        exit 6
      }
    }
  ' "$CHANGELOG" > "$tmp_changelog"
  mv "$tmp_changelog" "$CHANGELOG"
}

check_sync() {
  if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: missing ${VERSION_FILE}" >&2
    exit 1
  fi

  version="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
  if [ -z "$version" ]; then
    echo "ERROR: ${VERSION_FILE} is empty" >&2
    exit 1
  fi

  expected="${IMAGE_REPO}:${version}"
  fail=0

  docker_value="$(sed -n 's/^ARG BUILD_FROM=//p' "$DOCKERFILE")"
  if [ "$docker_value" != "$expected" ]; then
    echo "Mismatch: Dockerfile has '${docker_value}', expected '${expected}'" >&2
    fail=1
  fi

  if [ ! -x "$CHECK_SCRIPT" ]; then
    echo "ERROR: missing executable ${CHECK_SCRIPT}" >&2
    fail=1
  elif ! "$CHECK_SCRIPT" --quiet; then
    fail=1
  fi

  latest_bump_line="$(awk '
    BEGIN { in_latest = 0 }
    /^## / {
      if (!in_latest) {
        in_latest = 1
        next
      }
      in_latest = 0
    }
    in_latest && /^- feat: bump Statistics for Strava to v[0-9]/ {
      print
      exit
    }
  ' "$CHANGELOG")"

  expected_line="- feat: bump Statistics for Strava to ${version} [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)"
  if [ "$latest_bump_line" != "$expected_line" ]; then
    echo "Mismatch: latest changelog bump line is '${latest_bump_line}', expected '${expected_line}'" >&2
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then
    exit 1
  fi

  echo "OK: upstream version is synchronized (${version})"
}

print_commit_message() {
  version="$1"
  printf '\nfeat: bump upstream to %s\n' "$version"
}

append_changed_file() {
  file="$1"
  if [ -z "${CHANGED_FILES:-}" ]; then
    CHANGED_FILES="$file"
  else
    CHANGED_FILES="${CHANGED_FILES}
$file"
  fi
}

run_bump() {
  version="$1"

  IMAGE_REF="${IMAGE_REPO}:${version}"
  CHANGED_FILES=""
  LAST_BUMP_CHANGED="0"

  before_version_file="$(mktemp)"
  before_dockerfile="$(mktemp)"
  before_config_yaml="$(mktemp)"
  before_changelog="$(mktemp)"

  previous_upstream_version="$(tr -d ' \t\r\n' < "$VERSION_FILE" 2>/dev/null || true)"

  if [ -f "$VERSION_FILE" ]; then
    cp "$VERSION_FILE" "$before_version_file"
  else
    : > "$before_version_file"
  fi
  cp "$DOCKERFILE" "$before_dockerfile"
  cp "$CONFIG_YAML" "$before_config_yaml"
  cp "$CHANGELOG" "$before_changelog"

  printf '%s\n' "$version" > "$VERSION_FILE"

  tmp_docker="$(mktemp)"
  awk -v image_ref="$IMAGE_REF" '
    BEGIN { updated = 0 }
    /^ARG BUILD_FROM=/ {
      print "ARG BUILD_FROM=" image_ref
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print "ERROR: ARG BUILD_FROM=... not found in Dockerfile" > "/dev/stderr"
        exit 2
      }
    }
  ' "$DOCKERFILE" > "$tmp_docker"
  mv "$tmp_docker" "$DOCKERFILE"

  if [ "$previous_upstream_version" != "$version" ]; then
    current_addon_version="$(get_config_version)"
    if [ -z "$current_addon_version" ]; then
      echo "ERROR: could not parse add-on version from ${CONFIG_YAML}" >&2
      exit 7
    fi
    next_addon_version="$(next_patch_version "$current_addon_version")"
    set_config_version "$next_addon_version"
    prepend_changelog_release "$next_addon_version" "$version"
  fi

  if ! cmp -s "$before_version_file" "$VERSION_FILE"; then
    append_changed_file "$VERSION_FILE"
  fi
  if ! cmp -s "$before_dockerfile" "$DOCKERFILE"; then
    append_changed_file "$DOCKERFILE"
  fi
  if ! cmp -s "$before_config_yaml" "$CONFIG_YAML"; then
    append_changed_file "$CONFIG_YAML"
  fi
  if ! cmp -s "$before_changelog" "$CHANGELOG"; then
    append_changed_file "$CHANGELOG"
  fi

  rm -f "$before_version_file" "$before_dockerfile" "$before_config_yaml" "$before_changelog"

  if [ -n "$CHANGED_FILES" ]; then
    LAST_BUMP_CHANGED="1"
    echo "Updated upstream version to ${version}"
    echo "Changed files:"
    printf '%s\n' "$CHANGED_FILES" | sed 's/^/  - /'
  else
    echo "No changes needed (already at ${version})"
  fi
}

normalize_version() {
  input="$1"
  case "$input" in
    v*) echo "$input" ;;
    *) echo "v${input}" ;;
  esac
}

fetch_latest_upstream_version() {
  tags_output="$(git ls-remote --tags --refs "$UPSTREAM_GIT_URL" 2>/dev/null || true)"
  if [ -z "$tags_output" ]; then
    echo "ERROR: failed to fetch tags from ${UPSTREAM_GIT_URL}" >&2
    exit 1
  fi

  latest="$(
    printf '%s\n' "$tags_output" |
      awk '
        {
          ref = $2
          if (ref ~ /^refs\/tags\/v?[0-9]+\.[0-9]+\.[0-9]+$/) {
            sub(/^refs\/tags\/v?/, "", ref)
            print ref
          }
        }
      ' |
      sort -u -t. -k1,1n -k2,2n -k3,3n |
      tail -n1
  )"

  if [ -z "$latest" ]; then
    echo "ERROR: could not parse release tags (vX.Y.Z or X.Y.Z) from ${UPSTREAM_GIT_URL}" >&2
    exit 1
  fi

  echo "v${latest}"
}

if [ "${1:-}" = "" ]; then
  resolved_version="$(fetch_latest_upstream_version)"
  echo "Resolved upstream version (git tags): ${resolved_version}"
  run_bump "$resolved_version"
  check_sync
  if [ "${LAST_BUMP_CHANGED:-0}" = "1" ]; then
    print_commit_message "$resolved_version"
  fi
  exit 0
fi

MODE="$1"

if [ "$MODE" = "check" ]; then
  check_sync
  exit 0
fi

if [ "$MODE" != "bump" ]; then
  usage
  exit 1
fi

if [ "${2:-}" = "" ]; then
  VERSION="$(fetch_latest_upstream_version)"
  echo "Resolved upstream version (git tags): ${VERSION}"
else
  VERSION="$(normalize_version "$2")"
  echo "Resolved upstream version (explicit): ${VERSION}"
fi

run_bump "$VERSION"
