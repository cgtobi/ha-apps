# Vendored pre-squash migrations

Upstream Dreeve migrations, copied verbatim out of the image recorded in
`.source` (MIT, © the Dreeve authors — see
<https://github.com/dreeveapp/dreeve>). Not add-on code: do not edit them.

They are the migrations of the release immediately before upstream's current
migration squash. A squashed release refuses to migrate a database that did not
come through that release, and Home Assistant cannot be asked to update an
add-on through an intermediate version, so the add-on replays these itself for a
database that skipped it — see `rootfs/usr/local/bin/sfs-migration-gate.sh`.

They are vendored rather than copied out of the upstream image during the build:
a second build stage would pull ~370MB of image for 160K of files on every
rebuild, including rebuilds on the user's own Home Assistant box. A squashed
history never changes, so there is nothing to keep in sync until upstream
squashes again.

Refresh (only when upstream squashes again, which fails the build until it is
done):

    scripts/sync-pre-squash-migrations.sh sync statistics_for_strava ghcr.io/dreeveapp/dreeve:<tag>

then point `ARG PRE_SQUASH_FROM` and `ARG PRE_SQUASH_ADDON_VERSION` in the
Dockerfile at that image and at the add-on release that shipped it.
