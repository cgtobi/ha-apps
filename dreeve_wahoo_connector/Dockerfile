ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve-wahoo-connector:sha-eb2e511
FROM ${BUILD_FROM}

LABEL \
    org.opencontainers.image.title="Dreeve Wahoo Connector" \
    org.opencontainers.image.description="Imports Wahoo workouts into Dreeve" \
    org.opencontainers.image.source="https://github.com/cgtobi/ha-apps" \
    org.opencontainers.image.url="https://github.com/dreeveapp/dreeve-wahoo-connector" \
    org.opencontainers.image.licenses="MIT" \
    io.hass.type="app" \
    io.hass.name="Dreeve Wahoo Connector" \
    io.hass.description="Imports Wahoo workouts into Dreeve" \
    io.hass.url="https://docs.dreeve.app/#/integrations/wahoo-connector"

# The add-on's own logic lands under /usr/local/lib/dreeve-ha. Nothing is installed here: the image
# already carries the Python the connector itself runs on. PYTHONPATH is deliberately NOT set as an
# image-wide ENV - this directory would join the upstream connector's import path, in front of its own
# `app` package. ha-start.sh sets it per invocation instead.
COPY rootfs /

RUN chmod +x /usr/local/bin/ha-start.sh

# Liveness only. Unlike the garmin and polar add-ons, there is no upstream HEALTHCHECK to replace:
# this image ships none, so Supervisor's `AppState.STARTUP if self.instance.healthcheck else
# AppState.STARTED` branch already takes the STARTED path and nothing has to be fixed. This check is
# added for what it reports, not to unblock startup - a health verdict in `docker ps` and the same
# signal the watchdog uses.
#
# What must never be written here is `HEALTHCHECK NONE`, the one option that is strictly worse than
# both: it puts Test:["NONE"] into the image config rather than removing the key, so Supervisor sees
# *a* healthcheck and waits for a verdict Docker never emits for a disabled check - burning the full
# 120s STARTUP_TIMEOUT on every start. That cost the polar add-on two releases.
#
# A TCP connect to the dashboard port is the same signal as the watchdog in config.yaml: healthy
# exactly while the app is listening, indifferent to whether anyone has authorized. The port is
# hardcoded because PORT is add-on-owned (see dreeve_ha/env.py) and a HEALTHCHECK cannot read it.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/python", "-c", "import socket; socket.create_connection(('127.0.0.1', 8080), 3).close()"]

# Replaces the upstream CMD, which ha-start.sh runs itself once the environment is ready.
ENTRYPOINT ["/usr/local/bin/ha-start.sh"]
CMD []
