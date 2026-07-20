ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve:v5.0.1
FROM ${BUILD_FROM}

LABEL \
    org.opencontainers.image.title="Dreeve" \
    org.opencontainers.image.description="Dashboard for your sports & fitness data" \
    org.opencontainers.image.source="https://github.com/cgtobi/ha-apps" \
    org.opencontainers.image.url="https://github.com/dreeveapp/dreeve" \
    org.opencontainers.image.licenses="MIT" \
    io.hass.type="app" \
    io.hass.name="Dreeve" \
    io.hass.description="Dashboard for your sports & fitness data" \
    io.hass.url="https://docs.dreeve.app"

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
