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
#   3. The config/packages/flysystem.yaml override drifts from upstream's storage
#      list. flysystem-bundle autowires each `FilesystemOperator $xStorage`
#      param by storage key, and an unmatched param silently falls back to
#      default.storage (/var/www) — no error, writes land in the container layer
#      and reads come up empty. Our copy may only redirect `directory:` for
#      file.storage and database.storage; everything else must be upstream's
#      verbatim. Both drifts went unnoticed: upstream re-added build.storage in
#      v5.2.1 and we never mapped it, and v5.6.0 moved countries-geography.storage
#      to %kernel.project_dir%/resources/countries while ours kept the old path.
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

# --- flysystem.yaml override: same storages as upstream, only data dirs moved --
#
# Parsed with symfony/yaml from the image's own vendor dir (the image has no
# yq/python, and a text diff would trip over quoting and key order). Storage
# blocks are compared as normalized arrays — adapter, options, visibility, all
# of it — with the directory excluded only for the two storages we redirect.
# The directory sits under `options:` in the bundle's long form and under the
# adapter key (`local:`) in its shorthand, which upstream uses since v5.8.0;
# both are excluded, so the check holds whichever form upstream picks.
#
# Skipped when no staging dir is given or we do not override the file.
if [ -n "$STAGE" ] && [ -f "$STAGE/var/www/config/packages/flysystem.yaml" ]; then
  upstream=/var/www/config/packages/flysystem.yaml
  ours="$STAGE/var/www/config/packages/flysystem.yaml"

  [ -f "$upstream" ] \
    || fail "config/packages/flysystem.yaml overrides a file the upstream image does not have (upstream renamed or moved it — resync the override)"

  drift="$(php -- "$upstream" "$ours" <<'PHP'
<?php
require '/var/www/vendor/autoload.php';

use Symfony\Component\Yaml\Yaml;

// Storages whose directory we redirect to /data; nothing else may differ.
$redirected = ['file.storage', 'database.storage'];

$storages = static function (string $path): array {
    try {
        $yaml = Yaml::parseFile($path);
    } catch (\Throwable $e) {
        echo "cannot parse $path: {$e->getMessage()}\n";
        exit(0);
    }
    $s = $yaml['flysystem']['storages'] ?? null;
    if (!is_array($s)) {
        echo "$path has no flysystem: storages: map\n";
        exit(0);
    }
    return $s;
};

$normalize = static function ($v) use (&$normalize) {
    if (!is_array($v)) {
        return $v;
    }
    ksort($v);
    return array_map($normalize, $v);
};

$up = $storages($argv[1]);
$ours = $storages($argv[2]);

$missing = array_diff(array_keys($up), array_keys($ours));
$extra = array_diff(array_keys($ours), array_keys($up));
if ($missing) {
    echo 'missing storage(s) upstream has: ', implode(' ', $missing), "\n";
}
if ($extra) {
    echo 'extra storage(s) upstream does not have: ', implode(' ', $extra), "\n";
}

foreach (array_intersect(array_keys($up), array_keys($ours)) as $key) {
    $u = $up[$key];
    $o = $ours[$key];
    if (in_array($key, $redirected, true)) {
        unset(
            $u['options']['directory'], $o['options']['directory'],
            $u['local']['directory'], $o['local']['directory'],
        );
    }
    if ($normalize($u) !== $normalize($o)) {
        $flags = JSON_UNESCAPED_SLASHES;
        echo "$key differs from upstream: upstream ", json_encode($up[$key], $flags),
            ' ours ', json_encode($ours[$key], $flags), "\n";
    }
}
PHP
)" || fail "config/packages/flysystem.yaml check could not run (php exited non-zero)"

  [ -z "$drift" ] \
    || fail "config/packages/flysystem.yaml drifted from upstream's storages — resync it against the current image (keys must match; only file/database directory may differ):
$drift"
fi

echo "sfs-verify-overrides: ok"
