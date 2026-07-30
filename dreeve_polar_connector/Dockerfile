ARG BUILD_FROM=ghcr.io/cgtobi/dreeve-polar-connector:0.1.0
FROM ${BUILD_FROM}

LABEL \
    org.opencontainers.image.title="Dreeve Polar Connector" \
    org.opencontainers.image.description="Imports Polar Flow training sessions into Dreeve" \
    org.opencontainers.image.source="https://github.com/cgtobi/ha-apps" \
    org.opencontainers.image.url="https://github.com/cgtobi/dreeve-polar-connector" \
    org.opencontainers.image.licenses="GPL-3.0-or-later" \
    io.hass.type="app" \
    io.hass.name="Dreeve Polar Connector" \
    io.hass.description="Imports Polar Flow training sessions into Dreeve" \
    io.hass.url="https://github.com/cgtobi/dreeve-polar-connector"

# The add-on's own logic lands under /usr/local/lib/dreeve-ha. Nothing is installed here: the image
# already carries the Python the connector itself runs on. PYTHONPATH is deliberately NOT set as an
# image-wide ENV - a venv still honours it, so this directory would join the upstream connector's
# import path and any name collision would silently shadow its modules. ha-start.sh sets it per
# invocation instead.
COPY rootfs /

RUN chmod +x /usr/local/bin/ha-start.sh

# Liveness only, replacing the upstream HEALTHCHECK rather than disabling it.
#
# Upstream's runs `dreeve-polar-connector healthcheck`, which reports unhealthy until someone has
# completed the Polar authorization - by design upstream, and not something a restart repairs - and
# which only ever sees the image's static env, never what ha-start.sh exports after sourcing its env
# file.
#
# `HEALTHCHECK NONE` is not the answer: it writes Test:["NONE"] into the image config, so Supervisor
# still sees *a* healthcheck and holds the app in state STARTUP waiting for a health verdict Docker
# will never emit for a disabled check - every start then burns the full 120s STARTUP_TIMEOUT.
#
# A TCP connect to the status port is the same signal as the watchdog in config.yaml: healthy exactly
# while the sync process is alive, indifferent to authorization. The port is hardcoded because
# HTTP_ADDR is add-on-owned (see dreeve_ha/env.py) and a HEALTHCHECK cannot read it anyway.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/opt/venv/bin/python", "-c", "import socket; socket.create_connection(('127.0.0.1', 8080), 3).close()"]

# Replaces the upstream entrypoint, which ha-start.sh execs itself once the environment is ready.
ENTRYPOINT ["/usr/local/bin/ha-start.sh"]
CMD []
