#!/bin/sh
# Build-time sanity check for the upstream files we override in rootfs/var/www.
#
# Two failure modes, both silent at build time without this script.
#
# (A third, a yaml override naming a class upstream renamed, is gone with the
# framework.yaml override: config/packages/zz-ha-ingress.yaml shadows no upstream
# file and names no class.)
#
#   1. An override is a stale copy of an upstream file that has since grown
#      something. Our copy wins, so whatever upstream added is simply gone:
#      v5.2.3 added the `filteredUrl` Twig function and the
#      `window.dreeve.pageFragment` constants, and the stale copies dropped
#      both — the SPA then rendered the menu and no page content at all.
#
#   2. An override imports an App class upstream has since moved. Only the
#      `use` line names it, so the check above cannot see it: v5.3.0 moved
#      ApiFragmentRequestHandler into App\Controller\Api\Internal and the
#      stale import in IndexPage.php would have been a fatal on every render.
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

# --- php overrides may only add to upstream, never drop from it -------------
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

    # Every App class our copy imports must exist in the upstream image. PSR-4
    # maps App\Foo\Bar to src/Foo/Bar.php, so a moved or renamed class is a
    # missing file. Catches what the literal check cannot see: a `use` line is
    # not a quoted literal, and the class name never appears anywhere else.
    unknown="$(
      sed -n 's/^use \(App\\[A-Za-z0-9_\\]*\);$/\1/p' "$ours" | while IFS= read -r class; do
        class_rel="$(printf '%s\n' "$class" | tr '\\' '/')"
        class_rel="${class_rel#App/}"
        [ -f "/var/www/src/${class_rel}.php" ] || printf '%s ' "$class"
      done
    )"

    [ -z "$unknown" ] \
      || fail "$rel imports ${unknown}which the upstream image does not have (upstream renamed or moved it — resync the override)"
  done
fi

echo "sfs-verify-overrides: ok"
