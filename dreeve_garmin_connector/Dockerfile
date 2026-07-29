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

# The upstream image's HEALTHCHECK shells out to `dreeve-garmin-connector healthcheck`, but a
# HEALTHCHECK process only sees the image's static env - not the variables ha-start.sh exports after
# sourcing /run/dreeve-ha.env - so it reports "GARMIN_EMAIL is required" forever and the container
# always looks unhealthy in `docker ps`, however well configured it is. Home Assistant does not use
# Docker's health status anyway: liveness is the TCP watchdog declared in config.yaml, which is also
# the only signal we want, since the connector's own health turns unhealthy on broken Garmin
# credentials, and no restart fixes those.
HEALTHCHECK NONE

# Replaces the upstream entrypoint, which ha-start.sh execs itself once the environment is ready.
ENTRYPOINT ["/usr/local/bin/ha-start.sh"]
CMD []
