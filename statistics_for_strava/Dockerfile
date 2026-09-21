ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve:v5.4.0

# Where the vendored pre-squash migrations came from. They are the migrations of
# the upstream release immediately before the migration squash BUILD_FROM carries,
# and the add-on replays them for a database that skipped that release — see
# sfs-migration-gate.sh for why that stepping stone cannot be enforced through
# Home Assistant's update flow.
#
# This is provenance, not a build stage: a second FROM would make every build,
# including a rebuild on the user's own Home Assistant box, pull ~370MB of image
# for 160K of migrations. scripts/sync-pre-squash-migrations.sh vendors them and
# records the image they came from; the build fails if this value and that record
# disagree. Bumped only when upstream squashes again, which
# sfs-prepare-migration-guard.sh fails the build over rather than leaving to be
# noticed.
ARG PRE_SQUASH_FROM=ghcr.io/dreeveapp/dreeve:v5.3.3
# The add-on version that shipped PRE_SQUASH_FROM — what the user has to reinstall
# when the gate cannot close the gap itself. Home Assistant knows add-on versions,
# not upstream tags, so the instructions have to name this one.
ARG PRE_SQUASH_ADDON_VERSION=0.5.32

FROM ${BUILD_FROM}
ARG PRE_SQUASH_FROM
ARG PRE_SQUASH_ADDON_VERSION

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

# The vendored pre-squash migrations, and the build-time half of the squash gate:
# it reads the two migration ids out of the image's own MigrationSquashHandler
# (hardcoding them would keep matching the previous squash after upstream does the
# next one), checks the vendored copy is intact and came from PRE_SQUASH_FROM, that
# it can actually reach the baseline those ids name, and that every App class those
# migrations import still exists here.
COPY pre-squash-migrations /usr/local/share/sfs/pre-squash-migrations
RUN sh /usr/local/bin/sfs-prepare-migration-guard.sh "${PRE_SQUASH_FROM}" "${PRE_SQUASH_ADDON_VERSION}"

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
