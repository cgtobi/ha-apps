#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEFAULT_ADDON="statistics_for_strava"
CHECK_SCRIPT="${ROOT_DIR}/scripts/check-release-consistency.sh"

read_repo_field() {
  field="$1"
  sed -n "s/^${field}=//p" "$REPO_FILE" | head -n1
}

# Resolves every per-add-on path and upstream fact from the add-on name, so nothing about a third
# add-on needs a code change here. Must run before any bump/check helper.
select_addon() {
  ADDON="${1:-$DEFAULT_ADDON}"
  ADDON_DIR="${ROOT_DIR}/${ADDON}"
  if [ ! -f "${ADDON_DIR}/config.yaml" ]; then
    echo "ERROR: unknown add-on '${ADDON}'" >&2
    exit 1
  fi
  VERSION_FILE="${ADDON_DIR}/.upstream-version"
  DOCKERFILE="${ADDON_DIR}/Dockerfile"
  CONFIG_YAML="${ADDON_DIR}/config.yaml"
  CHANGELOG="${ADDON_DIR}/CHANGELOG.md"
  REPO_FILE="${ADDON_DIR}/.upstream-repo"
  if [ ! -f "$REPO_FILE" ]; then
    echo "ERROR: missing ${REPO_FILE}" >&2
    exit 1
  fi
  IMAGE_REPO="$(read_repo_field image_repo)"
  UPSTREAM_GIT_URL="$(read_repo_field git_url)"
  DISPLAY_NAME="$(read_repo_field display_name)"
  CHANGELOG_URL="$(read_repo_field changelog_url)"
  # Image tags do not always carry the git tag's shape. dreeve and dreeve-garmin-connector publish
  # v-prefixed tags (v1.0.0); dreeve-polar-connector publishes bare ones (0.1.0), because
  # docker/metadata-action's {{version}} strips the leading v. Absent field means 'v', which is what
  # every add-on assumed before this was configurable - so an empty value has to be distinguishable
  # from a missing one, hence the grep rather than a defaulted read.
  if grep -q '^tag_prefix=' "$REPO_FILE"; then
    TAG_PREFIX="$(read_repo_field tag_prefix)"
  else
    TAG_PREFIX="v"
  fi
}

usage() {
  echo "Usage:"
  echo "  $0 bump [addon] [upstream-version-tag]"
  echo "  $0 check [addon]"
  echo "  $0 [addon]"
  echo "Examples:"
  echo "  $0 bump statistics_for_strava v5.1.0"
  echo "  $0 bump dreeve_garmin_connector"
  echo "  $0 check dreeve_garmin_connector"
  echo "  $0"
  echo "The add-on defaults to ${DEFAULT_ADDON}."
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
  awk -v addon_version="$addon_version" -v upstream_version="$upstream_version" \
      -v display_name="$DISPLAY_NAME" -v changelog_url="$CHANGELOG_URL" '
    BEGIN {
      inserted = 0
      skip_first_blank_after_header = 0
      new_line = "- feat: bump " display_name " to " upstream_version " [Changelog](" changelog_url ")"
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
    echo "Mismatch: ${ADDON}: Dockerfile has '${docker_value}', expected '${expected}'" >&2
    fail=1
  fi

  if [ ! -x "$CHECK_SCRIPT" ]; then
    echo "ERROR: missing executable ${CHECK_SCRIPT}" >&2
    fail=1
  elif ! "$CHECK_SCRIPT" --quiet; then
    fail=1
  fi

  # The pinned tag must be recorded somewhere in the changelog - not necessarily in the newest
  # release. Add-on releases that carry only fixes or documentation are normal (see 0.5.5, 0.5.8), and
  # requiring the newest section to hold a bump line would fail on every one of them.
  expected_line="- feat: bump ${DISPLAY_NAME} to ${version} [Changelog](${CHANGELOG_URL})"
  # -e, because the expected line starts with '-' and BSD grep would read it as an option.
  if ! grep -Fqx -e "$expected_line" "$CHANGELOG"; then
    echo "Mismatch: ${ADDON}: no changelog entry for the pinned upstream version; expected a line '${expected_line}'" >&2
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then
    exit 1
  fi

  echo "OK: ${ADDON}: upstream version is synchronized (${version})"
}

print_commit_message() {
  version="$1"
  printf '\nfeat: bump %s upstream to %s\n' "$ADDON" "$version"
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
  # Accepts either shape on the command line and renders the one this upstream actually publishes,
  # so `bump dreeve_polar_connector v0.2.0` still pins the existing image tag 0.2.0.
  input="$1"
  echo "${TAG_PREFIX}${input#v}"
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

  # The git tag's own prefix is discarded above; what goes into the pin is the prefix this upstream's
  # published image tags use, which is not always the same thing.
  echo "${TAG_PREFIX}${latest}"
}

MODE="${1:-}"

case "$MODE" in
  check)
    select_addon "${2:-}"
    check_sync
    exit 0
    ;;
  bump)
    ;;
  *)
    # No mode given: resolve the latest upstream tag and bump. The single argument, if any, is an
    # add-on name ("$0 dreeve_garmin_connector"); anything else is a typo.
    if [ -n "$MODE" ] && [ ! -f "${ROOT_DIR}/${MODE}/config.yaml" ]; then
      usage
      exit 1
    fi
    select_addon "$MODE"
    resolved_version="$(fetch_latest_upstream_version)"
    echo "Resolved upstream version (git tags): ${resolved_version}"
    run_bump "$resolved_version"
    check_sync
    if [ "${LAST_BUMP_CHANGED:-0}" = "1" ]; then
      print_commit_message "$resolved_version"
    fi
    exit 0
    ;;
esac

# bump [addon] [tag]: the add-on argument is optional, so decide by whether it names a directory.
if [ -n "${2:-}" ] && [ -f "${ROOT_DIR}/${2}/config.yaml" ]; then
  select_addon "$2"
  TAG="${3:-}"
else
  select_addon
  TAG="${2:-}"
fi

# A leftover argument that is neither an add-on name nor a version tag is a typo: refuse it instead
# of pinning the default add-on to a nonsense image reference.
if [ -n "$TAG" ]; then
  case "$TAG" in
    v[0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*.[0-9]*) ;;
    *)
      echo "ERROR: '${TAG}' is neither a known add-on nor a version tag (vX.Y.Z)" >&2
      exit 1
      ;;
  esac
fi

if [ -z "$TAG" ]; then
  VERSION="$(fetch_latest_upstream_version)"
  echo "Resolved upstream version (git tags): ${VERSION}"
else
  VERSION="$(normalize_version "$TAG")"
  echo "Resolved upstream version (explicit): ${VERSION}"
fi

run_bump "$VERSION"
