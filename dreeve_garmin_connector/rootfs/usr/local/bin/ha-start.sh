#!/bin/sh
# Add-on entrypoint. Prepares the connector's environment, makes sure a Garmin session exists, starts
# the status logger, then hands over to the upstream entrypoint so its TZ and PUID handling still run.
set -eu

PYTHON=/opt/venv/bin/python
ENV_FILE=/run/dreeve-ha.env
# Scoped to this add-on's own Python calls. Never exported: the connector is exec'd below and would
# otherwise inherit it, putting this directory on its import path.
ADDON_LIB=/usr/local/lib/dreeve-ha

log() {
  echo "$(date +"%Y-%m-%dT%H:%M:%S%z") [garmin] $*"
}

if ! PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha.prepare; then
  log "FATAL: could not prepare the connector environment"
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

# A missing session is not a startup failure: the connector stays up, reports unhealthy and the
# message above says what the user has to do.
PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha || log "No Garmin session yet; see the message above"

PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha.statusloop &

log "Starting the Garmin connector"
exec docker-entrypoint.sh run
