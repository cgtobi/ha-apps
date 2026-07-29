ARG BUILD_FROM=ghcr.io/cgtobi/dreeve-polar-connector:v1.0.0
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

# The upstream image's HEALTHCHECK runs `dreeve-polar-connector healthcheck`, which reports unhealthy
# until someone has completed the Polar authorization - by design upstream, and not something a
# restart can repair. It would also never see the variables ha-start.sh exports after sourcing its
# env file, since a HEALTHCHECK process only gets the image's static env. Home Assistant does not
# consult Docker's health status anyway: liveness is the TCP watchdog declared in config.yaml.
HEALTHCHECK NONE

# Replaces the upstream entrypoint, which ha-start.sh execs itself once the environment is ready.
ENTRYPOINT ["/usr/local/bin/ha-start.sh"]
CMD []
