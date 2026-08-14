"""Surfaces the connector's status in the add-on log, so a backfill or a missing login shows.

Only changed lines are logged, so a quiet log means nothing changed. Read failures are caught and
reported rather than ending the loop - a watcher that died would leave the same quiet log. A status
that stays unreadable is reported too, for the same reason: silence must never be the only account
of a dashboard that never came up.

Upstream ships no status command, so the source is its own dashboard API rather than a subprocess.
"""

from __future__ import annotations

import json
import logging
import os
import ssl
import sys
import time
import urllib.request

from dreeve_ha import env

# http first. https is tried second because USE_HTTPS is the documented way out when Wahoo refuses a
# plain-HTTP redirect; upstream serves one scheme or the other on the same port. Both are built from
# env.PORT rather than repeating the number: the port is add-on-owned there, and a copy here would
# leave this loop silently reading nothing if it ever moved - the exact failure the loop exists to
# eliminate.
STATUS_URLS = (
    "http://127.0.0.1:{0}/api/status".format(env.PORT),
    "https://127.0.0.1:{0}/api/status".format(env.PORT),
)
POLL_SECONDS = 300
TIMEOUT_SECONDS = 10
# Three polls, so about 15 minutes at POLL_SECONDS. Long enough that a slow boot or a single restart
# stays quiet, short enough that a dashboard which is never coming up is named the same day.
UNREADABLE_POLLS_BEFORE_WARNING = 3

# What "something changed" means. last_sync_history is upstream's own record of the last completed
# sync, which is what a user is actually waiting on, so it is compared as well as reported.
# Deliberately excludes the fields below, which move within a cycle whether or not anything
# happened: comparing them would emit a line per poll - a heartbeat that buries what is worth
# reading.
SIGNIFICANT = (
    "authenticated",
    "next_sync_time",
    "last_sync_history",
    "last_result_status",
)
# Everything compared above, plus total_downloaded, is_syncing and last_result_errors: reported in
# the line, never compared, because they carry the detail a user reads once a line has been earned.
FIELDS = SIGNIFICANT + ("total_downloaded", "is_syncing", "last_result_errors")

LEVELS = {
    "debug": logging.DEBUG,
    "info": logging.INFO,
    "warning": logging.WARNING,
    "error": logging.ERROR,
    "critical": logging.CRITICAL,
}

logger = logging.getLogger("dreeve-ha.status")


def flatten(payload):
    """Lifts the two fields nested under last_result, so one flat comparison covers them."""
    result = dict(payload)
    last_result = payload.get("last_result")
    if not isinstance(last_result, dict):
        # null until a sync has finished in this process, and a string if upstream ever changes shape.
        last_result = {}
    result["last_result_status"] = last_result.get("status")
    result["last_result_errors"] = last_result.get("errors")
    return result


def summarize(payload):
    return " ".join("{0}={1}".format(field, payload.get(field)) for field in FIELDS)


def signature(payload):
    """What is compared between polls: the reported line minus the fields that always move."""
    return tuple(
        json.dumps(payload.get(field), sort_keys=True, default=str) for field in SIGNIFICANT
    )


def level(environ=None):
    """The add-on's log_level option, which reaches this process as LOG_LEVEL in the sourced env."""
    environ = os.environ if environ is None else environ

    return LEVELS.get(environ.get("LOG_LEVEL", "").strip().lower(), logging.INFO)


def unverified_context():
    """A TLS context that accepts the certificate upstream generates.

    Verification is off because that certificate is self-signed by construction - upstream creates
    it itself when the redirect is https - and this connection never leaves the container.
    """
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def open_url(url):
    """Reads one URL."""
    context = unverified_context() if url.startswith("https://") else None
    with urllib.request.urlopen(url, timeout=TIMEOUT_SECONDS, context=context) as response:
        return response.read().decode("utf-8")


def read_status(open_url=open_url, urls=STATUS_URLS):
    """Returns the parsed status, or None while the dashboard is not answering usefully."""
    for url in urls:
        try:
            body = open_url(url)
        except Exception:
            continue
        try:
            payload = json.loads(body)
        except ValueError:
            # A 200 that is not JSON - an upstream error page, a proxy interstitial - says nothing
            # about whether the other scheme answers, so the next URL still gets its turn.
            continue
        if not isinstance(payload, dict):
            # flatten() copies the payload into a dict, which an array or a scalar cannot fill: the
            # shape is checked here so an unexpected body keeps this function's promise of None.
            continue
        return flatten(payload)
    return None


def poll_once(previous, emit, read=read_status, unreadable=0, warn=None):
    """Emits the status line when something significant changed.

    Returns (the next comparison value, the number of consecutive unreadable polls). An unreadable
    status is normal for the first seconds of a boot and so stays silent - but from here "not up
    yet" and "never coming up" are the same silence, so after UNREADABLE_POLLS_BEFORE_WARNING in a
    row it is said once, and then not again until a poll succeeds.
    """
    warn = logger.warning if warn is None else warn
    payload = read()
    if payload is None:
        unreadable += 1
        if unreadable == UNREADABLE_POLLS_BEFORE_WARNING:
            warn(
                "The connector status has been unreadable for {0} polls; the dashboard may not "
                "have started. Check the log above for the connector's own errors.".format(
                    unreadable
                )
            )
        return previous, unreadable
    current = signature(payload)
    if current != previous:
        emit(summarize(payload))
    return current, 0


def main(poll_seconds=POLL_SECONDS, sleep=time.sleep, read=read_status):
    logging.basicConfig(
        stream=sys.stdout, level=level(), format="%(asctime)s [%(name)s] %(message)s"
    )
    previous = None
    # Carried across iterations, or every poll would start from zero and the warning above would
    # never be reached.
    unreadable = 0
    previous_error = None
    while True:
        try:
            previous, unreadable = poll_once(
                previous, logger.info, read=read, unreadable=unreadable
            )
            previous_error = None
        except Exception as exception:
            # This loop is the only thing telling the user a sync is progressing, so it must not die:
            # a crashed watcher leaves the log quiet, which reads exactly like "healthy and
            # unchanged". Repeats of the same error stay silent, matching the on-change rule above.
            description = "{0}: {1}".format(type(exception).__name__, exception)
            if description != previous_error:
                logger.warning("Could not read the connector status (%s); still trying.", description)
                previous_error = description
            previous = None
        # Polling before sleeping means the first line appears immediately instead of after a full
        # interval - waiting a whole POLL_SECONDS before anything shows up would be indistinguishable
        # from the loop having died, which is the exact ambiguity this module exists to remove. The
        # first polls of a boot are usually unreadable, which poll_once keeps quiet until the count
        # above says otherwise.
        sleep(poll_seconds)


if __name__ == "__main__":
    main()
