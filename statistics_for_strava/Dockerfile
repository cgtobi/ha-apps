ARG BUILD_FROM=ghcr.io/robiningelbrecht/statistics-for-strava:v4.8.8
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

# The upstream ENTRYPOINT (added in v4.8.8) runs
#   flock /var/www/storage/database/migrate.lock php bin/console app:db:migrate
# before exec'ing our CMD. At that point our cont-init has not yet created the
# /var/www/storage -> /data/storage symlink, so /var/www/storage/database does
# not exist and flock crashes the container with
#   "flock: cannot open lock file /var/www/storage/database/migrate.lock".
# We run migrations ourselves in sfs-reconcile-config.sh (via app:db:migrate)
# after the symlink is in place, so clear the entrypoint and let CMD run direct.
ENTRYPOINT []

CMD ["sh", "/usr/local/bin/start.sh"]
