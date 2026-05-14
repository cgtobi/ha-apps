ARG BUILD_FROM=ghcr.io/robiningelbrecht/statistics-for-strava:v4.7.12
FROM ${BUILD_FROM}

LABEL \
    org.opencontainers.image.title="Statistics for Strava" \
    org.opencontainers.image.description="Strava statistics dashboard" \
    org.opencontainers.image.source="https://github.com/cgtobi/ha-apps" \
    org.opencontainers.image.url="https://github.com/robiningelbrecht/statistics-for-strava" \
    org.opencontainers.image.licenses="MIT" \
    io.hass.type="app" \
    io.hass.name="Statistics for Strava" \
    io.hass.description="Strava statistics dashboard" \
    io.hass.url="https://github.com/robiningelbrecht/statistics-for-strava"

RUN apk add --no-cache jq

COPY rootfs /

CMD ["sh", "/usr/local/bin/start.sh"]
