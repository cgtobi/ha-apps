#!/usr/bin/env sh
# Runs the add-on's unit tests. Host mode by default (standard library only, no Docker needed);
# --in-image builds the add-on and runs the same suites inside it.
set -eu

ADDON_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LIB_DIR="${ADDON_DIR}/rootfs/usr/local/lib/dreeve-ha"

if [ "${1:-}" = "--in-image" ]; then
  IMAGE="dreeve-garmin-addon:test"
  docker build -t "$IMAGE" "$ADDON_DIR"
  # PYTHONPATH is passed here rather than baked into the image, so it never joins the upstream
  # connector's own import path.
  exec docker run --rm --entrypoint /opt/venv/bin/python \
    -e PYTHONPATH=/usr/local/lib/dreeve-ha "$IMAGE" \
    -m unittest discover -s /usr/local/lib/dreeve-ha/tests -t /usr/local/lib/dreeve-ha -v
fi

exec env PYTHONPATH="$LIB_DIR" python3 -m unittest discover -s "${LIB_DIR}/tests" -t "$LIB_DIR" -v
