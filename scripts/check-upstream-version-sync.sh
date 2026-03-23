#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ADDON_DIR="${ROOT_DIR}/statistics_for_strava"
VERSION_FILE="${ADDON_DIR}/.upstream-version"
DOCKERFILE="${ADDON_DIR}/Dockerfile"
BUILD_YAML="${ADDON_DIR}/build.yaml"
IMAGE_REPO="robiningelbrecht/strava-statistics"

if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: missing ${VERSION_FILE}" >&2
  exit 1
fi

VERSION="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
if [ -z "$VERSION" ]; then
  echo "ERROR: ${VERSION_FILE} is empty" >&2
  exit 1
fi

EXPECTED="${IMAGE_REPO}:${VERSION}"
FAIL=0

docker_value="$(sed -n 's/^ARG BUILD_FROM=//p' "$DOCKERFILE")"
if [ "$docker_value" != "$EXPECTED" ]; then
  echo "Mismatch: Dockerfile has '${docker_value}', expected '${EXPECTED}'" >&2
  FAIL=1
fi

check_arch() {
  arch="$1"
  value="$(sed -n "s/^  ${arch}: //p" "$BUILD_YAML")"
  if [ "$value" != "$EXPECTED" ]; then
    echo "Mismatch: build.yaml ${arch} has '${value}', expected '${EXPECTED}'" >&2
    FAIL=1
  fi
}

check_arch amd64
check_arch aarch64
check_arch armv7

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "OK: upstream version is synchronized (${VERSION})"
