#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ADDON_DIR="${ROOT_DIR}/statistics_for_strava"
VERSION_FILE="${ADDON_DIR}/.upstream-version"
DOCKERFILE="${ADDON_DIR}/Dockerfile"
BUILD_YAML="${ADDON_DIR}/build.yaml"
CHANGELOG="${ADDON_DIR}/CHANGELOG.md"
IMAGE_REPO="robiningelbrecht/strava-statistics"

usage() {
  echo "Usage: $0 <upstream-version-tag>"
  echo "Example: $0 v4.7.5"
}

if [ "${1:-}" = "" ]; then
  usage
  exit 1
fi

VERSION="$1"
case "$VERSION" in
  v*) ;;
  *) VERSION="v${VERSION}" ;;
esac

IMAGE_REF="${IMAGE_REPO}:${VERSION}"

printf '%s\n' "$VERSION" > "$VERSION_FILE"

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

tmp_build="$(mktemp)"
awk -v image_ref="$IMAGE_REF" '
  BEGIN { a = 0; b = 0; c = 0 }
  /^  amd64:/   { print "  amd64: " image_ref; a = 1; next }
  /^  aarch64:/ { print "  aarch64: " image_ref; b = 1; next }
  /^  armv7:/   { print "  armv7: " image_ref; c = 1; next }
  { print }
  END {
    if (!(a && b && c)) {
      print "ERROR: expected amd64/aarch64/armv7 build_from entries in build.yaml" > "/dev/stderr"
      exit 3
    }
  }
' "$BUILD_YAML" > "$tmp_build"
mv "$tmp_build" "$BUILD_YAML"

tmp_changelog="$(mktemp)"
awk -v version="$VERSION" '
  BEGIN {
    new_line = "- feat: bump Statistics for Strava to " version " [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)"
    seen_heading = 0
    in_latest = 0
    replaced = 0
  }
  /^## / {
    if (!seen_heading) {
      seen_heading = 1
      in_latest = 1
      print
      next
    }
    if (in_latest && !replaced) {
      print ""
      print new_line
      replaced = 1
    }
    in_latest = 0
    print
    next
  }
  {
    if (in_latest && $0 ~ /^- feat: bump Statistics for Strava to v[0-9]/) {
      print new_line
      replaced = 1
      next
    }
    print
  }
  END {
    if (seen_heading && in_latest && !replaced) {
      print ""
      print new_line
      replaced = 1
    }
    if (!replaced) {
      print "ERROR: could not update latest changelog upstream bump entry" > "/dev/stderr"
      exit 4
    }
  }
' "$CHANGELOG" > "$tmp_changelog"
mv "$tmp_changelog" "$CHANGELOG"

echo "Updated upstream version to ${VERSION}"
echo "Synchronized:"
echo "  - ${VERSION_FILE}"
echo "  - ${DOCKERFILE}"
echo "  - ${BUILD_YAML}"
echo "  - ${CHANGELOG}"
