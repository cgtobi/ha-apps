#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOOKS_DIR="${ROOT_DIR}/.githooks"
PRE_COMMIT_HOOK="${HOOKS_DIR}/pre-commit"

if [ ! -f "$PRE_COMMIT_HOOK" ]; then
  echo "ERROR: missing ${PRE_COMMIT_HOOK}" >&2
  exit 1
fi

chmod +x "$PRE_COMMIT_HOOK"
git -C "$ROOT_DIR" config core.hooksPath .githooks

echo "Installed repo hooks:"
echo "  core.hooksPath=.githooks"
echo "  enabled: ${PRE_COMMIT_HOOK}"
