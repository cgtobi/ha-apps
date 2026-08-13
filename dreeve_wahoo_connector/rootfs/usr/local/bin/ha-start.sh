#!/bin/sh
# Add-on entrypoint. Prepares the connector's environment, starts the relay and the status logger,
# then runs the upstream app.
#
# There is no login step: Wahoo authorization is an OAuth redirect the connector's own dashboard
# serves on PORT. Until someone completes it, the connector runs, reports authenticated=false and
# delivers nothing - which the status logger below makes visible.
#
# There is also no upstream entrypoint to hand over to. This image ships CMD ["python", "-m",
# "app.main"] and nothing else, so this script execs that itself rather than trusting a CMD that could
# change - and TZ handling is the add-on's own, since upstream has none.
set -eu

PYTHON=/usr/local/bin/python
ENV_FILE=/run/dreeve-ha.env
# Scoped to this add-on's own Python calls. Never exported: the connector is exec'd below and would
# otherwise inherit it, putting this directory in front of upstream's own `app` package.
ADDON_LIB=/usr/local/lib/dreeve-ha

log() {
  echo "$(date +"%Y-%m-%dT%H:%M:%S%z") [wahoo] $*"
}

if ! PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha.prepare; then
  log "FATAL: could not prepare the connector environment"
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

# The relay copies what upstream downloaded into Dreeve's watch folder; upstream cannot be pointed at
# that folder directly, because it re-downloads anything Dreeve has deleted. See dreeve_ha/relay.py.
PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha.relay &
PYTHONPATH="$ADDON_LIB" "$PYTHON" -m dreeve_ha.statusloop &

log "Starting the Wahoo connector"
cd /workspace
exec "$PYTHON" -m app.main
