"""Surfaces the connector's status in the add-on log, so a backfill or a missing authorization shows.

Only changed lines are logged, so a quiet log means nothing changed. Read failures are caught and
reported rather than ending the loop - a watcher that died would leave the same quiet log.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import time

STATUS_COMMAND = ["/opt/venv/bin/dreeve-polar-connector", "status"]
POLL_SECONDS = 300

# What "something changed" means. Deliberately excludes the two timestamps below: they advance on
# every cycle whether or not anything happened, so comparing them would emit a line per cycle - a
# heartbeat that buries the lines worth reading.
SIGNIFICANT = (
    "healthy",
    "authorization",
    "authorizeUrl",
    "backlog",
    "backoffSeconds",
    "lastError",
)
# Reported, but not compared. authorizeUrl is null once authorized, so the line telling a user what to
# open disappears by itself; lastError carries whatever the last cycle failed with.
FIELDS = SIGNIFICANT + ("lastSuccessfulSync", "nextRunAt")

LEVELS = {
    "debug": logging.DEBUG,
    "info": logging.INFO,
    "warning": logging.WARNING,
    "error": logging.ERROR,
    "critical": logging.CRITICAL,
}

logger = logging.getLogger("dreeve-ha.status")


def summarize(payload):
    return " ".join("{0}={1}".format(field, payload.get(field)) for field in FIELDS)


def signature(payload):
    """What is compared between polls: the reported line minus the fields that always move."""
    return tuple(payload.get(field) for field in SIGNIFICANT)


def level(environ=None):
    """The add-on's log_level option, which reaches this process as LOG_LEVEL in the sourced env."""
    environ = os.environ if environ is None else environ

    return LEVELS.get(environ.get("LOG_LEVEL", "").strip().lower(), logging.INFO)


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
    """Emits the status line when something significant changed. Returns the next comparison value."""
    payload = read()
    if payload is None:
        return previous
    current = signature(payload)
    if current != previous:
        emit(summarize(payload))
    return current


def main(poll_seconds=POLL_SECONDS, sleep=time.sleep, read=read_status):
    logging.basicConfig(
        stream=sys.stdout, level=level(), format="%(asctime)s [%(name)s] %(message)s"
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
