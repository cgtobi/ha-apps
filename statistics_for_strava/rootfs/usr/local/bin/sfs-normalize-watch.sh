#!/bin/sh
set -eu

# Lowercase the extension of activity files in the watch dir.
#
# WHY: upstream's Path::getFilename() lowercases the extension when it rebuilds a
# filename, but WatchDirectory reads/deletes files by that rebuilt name against
# the real (case-preserved) name on disk. A file with an uppercase extension
# (e.g. Garmin devices export "*.FIT") is therefore listed by the import command
# but can never be read ("Unable to read file from location: watch/...fit" /
# "Failed to open stream: No such file or directory") and, crucially, never
# deleted -- so it is re-listed every cron cycle and the import aborts forever.
#
# The upstream code lives in the base image; patching it would drift on every
# version bump. Normalising the on-disk name in the (add-on owned) watch dir is
# decoupled from upstream and survives bumps. The rename is within a single
# directory, so it is atomic: an in-flight import either sees the old name (which
# harmlessly loops until the next pass) or the new one.
#
# Only the extensions the app actually parses are touched (fit/tcx/gpx). The base
# name is preserved; only the extension is lowercased.

WATCH_DIR="${1:-/var/www/watch}"

# Nothing to do if the watch dir is absent (e.g. Strava-API mode).
[ -d "$WATCH_DIR" ] || exit 0

for path in "$WATCH_DIR"/*; do
  # Guard against the literal glob when the dir is empty.
  [ -f "$path" ] || continue

  filename="$(basename "$path")"

  # Split base and extension on the LAST dot (matches pathinfo()).
  case "$filename" in
    *.*) ext="${filename##*.}"; base="${filename%.*}" ;;
    *) continue ;;  # no extension, skip
  esac

  ext_lower="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  # Only handle activity files the app parses.
  case "$ext_lower" in
    fit|tcx|gpx) ;;
    *) continue ;;
  esac

  # Already lowercase -> upstream reads it fine, leave it alone.
  [ "$ext" = "$ext_lower" ] && continue

  target="$WATCH_DIR/$base.$ext_lower"

  # If a lowercase-extension file already exists, do not clobber it; drop the
  # unreadable uppercase duplicate so it stops looping the importer.
  if [ -e "$target" ]; then
    rm -f "$path"
    continue
  fi

  mv "$path" "$target"
done
