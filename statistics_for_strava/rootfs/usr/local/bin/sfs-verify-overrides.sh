#!/bin/sh
# Build-time sanity check for the upstream files we override in rootfs/var/www.
#
# Those copies reference upstream classes by name. When a version bump renames
# one, nothing fails at build time: the app dies later during Symfony container
# compilation with an opaque error ("The service assets._default_package has a
# dependency on a non-existent service ..."), which the add-on surfaces only as a
# failing init step. Run from the Dockerfile so a bad override fails the build.
set -eu

fail() {
  echo "sfs-verify-overrides: $*" >&2
  exit 1
}

# config/packages/framework.yaml pins the asset version strategy class.
FRAMEWORK_YAML=/var/www/config/packages/framework.yaml
[ -f "$FRAMEWORK_YAML" ] || fail "missing $FRAMEWORK_YAML"

strategy="$(grep -m1 'version_strategy:' "$FRAMEWORK_YAML" | cut -d"'" -f2)"
[ -n "$strategy" ] || fail "no version_strategy found in $FRAMEWORK_YAML"

# App\Foo\Bar -> src/Foo/Bar.php
rel="$(printf '%s\n' "$strategy" | tr '\\' '/')"
rel="${rel#App/}"
[ -f "/var/www/src/${rel}.php" ] \
  || fail "framework.yaml references '${strategy}', but /var/www/src/${rel}.php does not exist (upstream renamed or moved it — resync the override)"

echo "sfs-verify-overrides: ok"
