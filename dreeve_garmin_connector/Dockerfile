ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve-garmin-connector:v1.0.0
FROM ${BUILD_FROM}

LABEL \
    org.opencontainers.image.title="Dreeve Garmin Connector" \
    org.opencontainers.image.description="Imports Garmin Connect activities into Dreeve" \
    org.opencontainers.image.source="https://github.com/cgtobi/ha-apps" \
    org.opencontainers.image.url="https://github.com/dreeveapp/dreeve-garmin-connector" \
    org.opencontainers.image.licenses="MIT" \
    io.hass.type="app" \
    io.hass.name="Dreeve Garmin Connector" \
    io.hass.description="Imports Garmin Connect activities into Dreeve" \
    io.hass.url="https://docs.dreeve.app/#/integrations/garmin-connect"

# The add-on's own logic lands under /usr/local/lib/dreeve-ha. Nothing is installed here: the image
# already carries the Python the connector itself runs on. PYTHONPATH is deliberately NOT set as an
# image-wide ENV - a venv still honours it, so this directory would join the upstream connector's
# import path and any name collision would silently shadow its modules. ha-start.sh sets it per
# invocation instead.
COPY rootfs /

RUN chmod +x /usr/local/bin/ha-start.sh

# Liveness only, replacing the upstream HEALTHCHECK rather than disabling it.
#
# Upstream's shells out to `dreeve-garmin-connector healthcheck`, but a HEALTHCHECK process only sees
# the image's static env - not the variables ha-start.sh exports after sourcing /run/dreeve-ha.env -
# so it reports "GARMIN_EMAIL is required" forever, however well configured the add-on is. Its verdict
# also turns unhealthy on broken Garmin credentials, which no restart fixes.
#
# `HEALTHCHECK NONE` is not the answer: it writes Test:["NONE"] into the image config, so Supervisor
# still sees *a* healthcheck and holds the app in state STARTUP waiting for a health verdict Docker
# will never emit for a disabled check - every start then burns the full 120s STARTUP_TIMEOUT.
#
# A TCP connect to the status port is the same signal as the watchdog in config.yaml: healthy exactly
# while the sync process is alive, indifferent to credentials. The port is hardcoded because
# HTTP_ADDR is add-on-owned (see dreeve_ha/env.py) and a HEALTHCHECK cannot read it anyway.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/opt/venv/bin/python", "-c", "import socket; socket.create_connection(('127.0.0.1', 8080), 3).close()"]

# Replaces the upstream entrypoint, which ha-start.sh execs itself once the environment is ready.
ENTRYPOINT ["/usr/local/bin/ha-start.sh"]
CMD []
