"""Delivers downloaded workouts into the Dreeve watch folder.

Upstream writes everything it downloads into $DATA_DIR/downloads and keeps it there: before fetching
a workout it asks whether that exact file still exists, so a file that vanished is downloaded again.
Dreeve deletes every file it imports. Pointing upstream straight at the watch folder therefore
re-downloads the whole SYNC_TIME_WINDOW on every cycle, forever - which is why this module exists.
The downloads directory stays the connector's own, and the files are copied out of it.

Interim. Once upstream can be told where to write and deduplicates on its own history, the connector
writes into the watch folder itself and this module goes away.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import sys
import time
from pathlib import Path

from dreeve_ha import env

LEDGER = env.STATE_DIR / "relayed.json"
# Short, because it costs one listdir of a small directory: upstream downloads in bursts after a cron
# fire, and a workout should not wait minutes on this side of the copy.
POLL_SECONDS = 15

logger = logging.getLogger("dreeve-ha.relay")


def read_ledger(path=LEDGER):
    """Returns the names already delivered. A damaged ledger reads as empty rather than failing.

    Re-delivering a file is harmless - Dreeve skips a workout it has already imported - while refusing
    to start would stop delivery altogether.
    """
    try:
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        return set()
    if not isinstance(payload, list):
        return set()
    return {str(item) for item in payload}


def write_ledger(delivered, path=LEDGER):
    """Records the delivered names. Sorted, so a diff of the file reads as a list of workouts.

    Written to a sibling and renamed, the same discipline deliver() uses. This process is a
    background child killed whenever the add-on stops, and a truncating write caught by that kill
    would leave a short file that read_ledger reads as empty - after which every .fit still in the
    downloads directory, which is never pruned, is delivered again in one burst.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(sorted(delivered)), encoding="utf-8")
    os.replace(str(temporary), str(path))


def pending(downloads_dir, delivered):
    """The .fit files not yet delivered.

    Only .fit: upstream downloads to <name>.fit.tmp and renames it into place, so anything else in
    there is either a download in flight or upstream's own bookkeeping.
    """
    try:
        names = sorted(entry.name for entry in Path(downloads_dir).iterdir())
    except FileNotFoundError:
        # Normal on a first boot, before upstream has created the directory.
        return []
    return [name for name in names if name.endswith(".fit") and name not in delivered]


def deliver(name, downloads_dir, watch_dir):
    """Copies one file in, atomically.

    Dreeve watches that folder and must never be handed a partial file.
    """
    source = Path(downloads_dir) / name
    destination = Path(watch_dir) / name
    temporary = Path(watch_dir) / (name + ".tmp")
    shutil.copyfile(str(source), str(temporary))
    os.replace(str(temporary), str(destination))


def relay_once(
    downloads_dir, watch_dir, delivered, ledger=LEDGER, emit=None, warn=None, reported=None
):
    """Delivers everything pending, returning the names delivered in this pass.

    Each delivery is guarded on its own. pending() is sorted, so a single file that can never be
    copied would otherwise hold up every workout after it in that order - and since the downloads
    directory is never pruned, that file stays there and the stall is permanent.

    `reported` is the caller's memory of the failures already logged, so a file that keeps failing
    produces one line rather than one every poll. Callers that pass nothing get one report per call.

    The ledger is written in a finally block: a pass that fails halfway must still record what it
    managed, or those files are delivered a second time.
    """
    emit = logger.info if emit is None else emit
    warn = logger.warning if warn is None else warn
    reported = set() if reported is None else reported
    handled = []
    try:
        for name in pending(downloads_dir, delivered):
            try:
                deliver(name, downloads_dir, watch_dir)
            except Exception as exception:
                # Not added to `delivered`, so it is retried on the next pass; the loop moves on so
                # the files behind it are not held hostage to it.
                if name not in reported:
                    warn(
                        "Could not deliver {0} ({1}: {2}); skipping it and continuing.".format(
                            name, type(exception).__name__, exception
                        )
                    )
                    reported.add(name)
                continue
            delivered.add(name)
            handled.append(name)
            emit("Delivered {0} into {1}".format(name, watch_dir))
    finally:
        if handled:
            try:
                write_ledger(delivered, ledger)
            except Exception as exception:
                # An exception raised from a finally block replaces the one already propagating, so
                # a failure to write bookkeeping would hide whatever the pass was really reporting.
                # Re-delivering what this ledger would have recorded is harmless; losing the reason
                # is not.
                warn(
                    "Could not record the delivered workouts ({0}: {1}); they may be delivered "
                    "again.".format(type(exception).__name__, exception)
                )
    return handled


def main(
    poll_seconds=POLL_SECONDS,
    sleep=time.sleep,
    downloads_dir=None,
    watch_dir=None,
    ledger=LEDGER,
    environ=None,
):
    environ = os.environ if environ is None else environ
    logging.basicConfig(
        stream=sys.stdout, level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s"
    )

    if downloads_dir is None:
        # From env, not from the process environment: DATA_DIR is add-on-owned, so the two can never
        # differ, and deriving this the way LEDGER is derived keeps the pair from drifting apart.
        downloads_dir = env.DOWNLOADS_DIR
    if watch_dir is None:
        watch_dir = environ.get("DREEVE_WATCH_DIR", "")
        if not watch_dir:
            # prepare.py always exports DREEVE_WATCH_DIR, so this means the env file was not
            # sourced. A loop that quietly delivered nothing would look exactly like a working relay
            # with no new workouts.
            logger.error(
                "DREEVE_WATCH_DIR is not set, so nothing can be delivered; the relay is not "
                "running."
            )
            return 1

    delivered = read_ledger(ledger)
    # Owned by the loop rather than by a pass, so a file that fails every 15 seconds is reported
    # once instead of once per poll.
    reported = set()
    previous_error = None
    while True:
        try:
            relay_once(downloads_dir, watch_dir, delivered, ledger=ledger, reported=reported)
            previous_error = None
        except Exception as exception:
            # Same reasoning as the status loop: a crashed relay is invisible, because "nothing
            # delivered" is also what a quiet, healthy relay looks like.
            description = "{0}: {1}".format(type(exception).__name__, exception)
            if description != previous_error:
                logger.warning("Could not deliver workouts (%s); still trying.", description)
                previous_error = description
        # Delivering before sleeping, so files already waiting at boot go out immediately.
        sleep(poll_seconds)


if __name__ == "__main__":
    sys.exit(main())
