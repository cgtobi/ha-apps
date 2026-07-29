"""Surfaces the connector's status in the add-on log, so a backfill or a dead session is visible.

Only changed lines are logged, so a quiet log means nothing changed. Read failures are caught and
reported rather than ending the loop - a watcher that died would leave the same quiet log.
"""

from __future__ import annotations

import json
import logging
import subprocess
import sys
import time

STATUS_COMMAND = ["/opt/venv/bin/dreeve-garmin-connector", "status"]
POLL_SECONDS = 300
FIELDS = (
    "healthy",
    "authentication",
    "backlog",
    "lastSuccessfulSync",
    "nextRunAt",
    "backoffSeconds",
)

logger = logging.getLogger("dreeve-ha.status")


def summarize(payload):
    return " ".join("{0}={1}".format(field, payload.get(field)) for field in FIELDS)


def read_status(run=subprocess.run, command=STATUS_COMMAND):
    """Returns the parsed status, or None while the connector is not answering yet."""
    completed = run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        return None
    try:
        return json.loads(completed.stdout)
    except ValueError:
        return None


def poll_once(previous, emit, read=read_status):
    """Emits the status line when it changed. Returns the line to compare against next time."""
    payload = read()
    if payload is None:
        return previous
    line = summarize(payload)
    if line != previous:
        emit(line)
    return line


def main(poll_seconds=POLL_SECONDS, sleep=time.sleep, read=read_status):
    logging.basicConfig(
        stream=sys.stdout, level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s"
    )
    previous = None
    previous_error = None
    while True:
        try:
            previous = poll_once(previous, logger.info, read=read)
            previous_error = None
        except Exception as exception:
            # This loop is the only thing telling the user a backfill is progressing, so it must not
            # die: a crashed watcher leaves the log quiet, which reads exactly like "healthy and
            # unchanged". Repeats of the same error stay silent, matching the on-change rule above.
            description = "{0}: {1}".format(type(exception).__name__, exception)
            if description != previous_error:
                logger.warning("Could not read the connector status (%s); still trying.", description)
                previous_error = description
            previous = None
        # Polling before sleeping means the first line appears immediately instead of after a full
        # interval - waiting a whole POLL_SECONDS before anything shows up would be indistinguishable
        # from the loop having died, which is the exact ambiguity this module exists to remove. An
        # unreadable status here is already silent and harmless, so there is no need to sleep first to
        # let the status server bind.
        sleep(poll_seconds)


if __name__ == "__main__":
    main()
