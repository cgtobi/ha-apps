#!/bin/sh
# Build-time sanity check for the upstream files we override in rootfs/var/www.
#
# Two failure modes, both silent at build time without this script:
#
#   1. An override references an upstream class by name and a version bump
#      renames it. The app dies later during Symfony container compilation with
#      an opaque error ("The service assets._default_package has a dependency on
#      a non-existent service ..."), surfaced only as a failing init step.
#
#   2. An override is a stale copy of an upstream file that has since grown
#      something. Our copy wins, so whatever upstream added is simply gone:
#      v5.2.3 added the `filteredUrl` Twig function and the
#      `window.dreeve.pageFragment` constants, and the stale copies dropped
#      both — the SPA then rendered the menu and no page content at all.
#
# Run from the Dockerfile with the rootfs staged (not yet installed), so both
# the upstream file and our copy are readable at once.
#
# Usage: sfs-verify-overrides.sh [staged-rootfs-dir]
set -eu

STAGE="${1:-}"

fail() {
  echo "sfs-verify-overrides: $*" >&2
  exit 1
}

# --- 1. yaml overrides may only name classes the upstream image ships --------

# config/packages/framework.yaml pins the asset version strategy class.
FRAMEWORK_YAML="${STAGE}/var/www/config/packages/framework.yaml"
[ -f "$FRAMEWORK_YAML" ] || fail "missing $FRAMEWORK_YAML"

strategy="$(grep -m1 'version_strategy:' "$FRAMEWORK_YAML" | cut -d"'" -f2)"
[ -n "$strategy" ] || fail "no version_strategy found in $FRAMEWORK_YAML"

# App\Foo\Bar -> src/Foo/Bar.php
rel="$(printf '%s\n' "$strategy" | tr '\\' '/')"
rel="${rel#App/}"
[ -f "/var/www/src/${rel}.php" ] \
  || fail "framework.yaml references '${strategy}', but /var/www/src/${rel}.php does not exist (upstream renamed or moved it — resync the override)"

# --- 2. php overrides may only add to upstream, never drop from it -----------
#
# Our copies are meant to be "upstream plus a small delta", so every single
# quoted literal upstream has — Twig function names, array keys, route paths,
# class-string references — must survive in ours. A literal that disappears
# means the copy predates an upstream change.
#
# Skipped when no staging dir is given (nothing to compare against).
if [ -n "$STAGE" ]; then
  overrides="$(cd "$STAGE/var/www" 2>/dev/null && find src -name '*.php' 2>/dev/null || true)"

  for rel in $overrides; do
    upstream="/var/www/$rel"
    ours="$STAGE/var/www/$rel"

    [ -f "$upstream" ] \
      || fail "$rel overrides a file the upstream image does not have (upstream renamed or moved it — resync the override)"

    missing="$(
      grep -o "'[^']*'" "$upstream" | sort -u | while IFS= read -r literal; do
        grep -qF -- "$literal" "$ours" || printf '%s ' "$literal"
      done
    )"

    [ -z "$missing" ] \
      || fail "$rel is a stale copy: upstream has ${missing}which our override dropped — resync it against the current image"
  done
fi

echo "sfs-verify-overrides: ok"
