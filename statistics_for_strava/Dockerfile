ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve:v5.2.3
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

# Staged, not installed yet: sfs-verify-overrides.sh compares each overridden
# file against the upstream copy it is meant to shadow, which is only possible
# while both exist. It fails the build when an override names a class upstream
# has renamed (an opaque init failure at runtime) or is a stale copy that drops
# something upstream added (silently missing features at runtime).
COPY rootfs /tmp/rootfs
RUN set -eu; \
    sh /tmp/rootfs/usr/local/bin/sfs-verify-overrides.sh /tmp/rootfs; \
    cp -a /tmp/rootfs/. /; \
    rm -rf /tmp/rootfs

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
