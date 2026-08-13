ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve:v5.2.1
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

# Base-path-proof the two hardcoded router targets in the SPA bundle.
#
# The router resolves a route by looking for a nav link whose href equals it
# (`a[href="<route>"][data-router-content-url]`). Every href is rendered through
# relativeUrl(), so behind a reverse proxy they all carry the base path — but the
# chart drill-downs call `navigateTo("/activities")` with a literal, which then
# matches no link and renders nothing. Upstream hits this on any subdirectory
# install; under Home Assistant ingress it is every install.
#
# Patched at image build (not at runtime) so the bundle is deterministic. The
# grep makes the build fail loudly if upstream changes these call sites, instead
# of silently shipping an unpatched bundle.
RUN set -eu; \
    app_js=/var/www/public/js/dist/app.min.js; \
    grep -q 'navigateTo("/activities")' "$app_js"; \
    sed -i 's#navigateTo("/activities")#navigateTo((window.dreeve?.appUrl?.basePath?"/"+window.dreeve.appUrl.basePath:"")+"/activities")#g' "$app_js"; \
    ! grep -q 'navigateTo("/activities")' "$app_js"

# Fail the build when an overridden upstream file references a class upstream has
# renamed or moved (at runtime that only shows up as an opaque init failure).
RUN sh /usr/local/bin/sfs-verify-overrides.sh

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
