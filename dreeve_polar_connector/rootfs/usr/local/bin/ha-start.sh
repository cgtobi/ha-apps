#!/bin/sh
# Add-on entrypoint. Prepares the connector's environment, starts the status logger, then hands over
# to the upstream entrypoint so its TZ and PUID handling still run.
#
# There is no login step: Polar authorization is an OAuth redirect the connector serves itself on
# HTTP_ADDR. Until someone completes it, the connector runs, says which URL to open, and delivers
# nothing - which the status logger below reports as authorization=required.
set -eu

PYTHON=/opt/venv/bin/python
ENV_FILE=/run/dreeve-ha.env
# Scoped to this add-on's own Python calls. Never exported: the connector is exec'd below and would
# otherwise inherit it, putting this directory on its import path.
ADDON_LIB=/usr/local/lib/dreeve-ha

log() {
  echo "$(date +"%Y-%m-%dT%H:%M:%S%z") [polar] $*"
}

if ! PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha.prepare; then
  log "FATAL: could not prepare the connector environment"
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha.statusloop &

log "Starting the Polar connector"
exec docker-entrypoint.sh run
