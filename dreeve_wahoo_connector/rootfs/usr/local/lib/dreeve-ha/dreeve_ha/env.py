"""Builds the environment the upstream connector reads at startup.

There is no add-on login step: Wahoo authorization is an OAuth redirect the connector's own dashboard
serves on PORT. That port is owned by the add-on - moving it would take away the dashboard, the
watchdog's only signal and the published host port in one go.

The two directories are split because they are kept for opposite reasons. STATE_DIR holds what must
survive a restart - the tokens, the sync history upstream deduplicates against, the certificate it
generates - while WATCH_DIR is Dreeve's watch folder, which Dreeve empties as it imports. Upstream
writes each download straight into it and never looks there again, so nothing has to be copied and
no downloaded file is kept twice.
"""

from __future__ import annotations

import re
import shlex
from pathlib import Path

DATA_DIR = Path("/data")
STATE_DIR = DATA_DIR / "state"
# Bound on all interfaces by upstream (app.run(host="0.0.0.0")): the TCP watchdog reaches it over the
# container's own address, and the `ports` entry in config.yaml publishes it on the host so a browser
# can complete the authorization. 8085 is upstream's own default, so its documentation and this
# add-on name the same number.
PORT = "8085"
# Upstream's own fallback is https://localhost:8085/callback, and any https redirect turns on a
# self-signed certificate, so an unconfigured add-on would answer its webui link with a certificate
# warning. This keeps the dashboard on plain HTTP; a login attempt then fails on Wahoo's own redirect
# mismatch, which names the actual problem.
FALLBACK_REDIRECT_URI = "http://localhost:{0}/callback".format(PORT)

# A key that is not a valid shell variable name would render an export line the entrypoint cannot
# source, taking the whole add-on down with a syntax error that names no option.
VARIABLE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# Overriding these would break persistence and the token store (DATA_DIR, STATE_DIR), the dashboard,
# the watchdog and the published port (PORT), or delivery into Dreeve (WATCH_DIR).
#
# VERIFY_FILES_ON_DISK is the one a user could plausibly switch on for the reassuring name, and it
# is the single most damaging setting here. It makes upstream confirm that an already-downloaded
# file is still on disk before skipping it - and under Dreeve it never is, because Dreeve deletes
# every file it imports. Every workout inside SYNC_TIME_WINDOW would then be downloaded again on
# every cron fire, spending Wahoo's quota and re-importing the same rides, with nothing in the log
# to say why. USE_HTTPS is deliberately absent: it is the documented way out when Wahoo refuses a
# plain-HTTP redirect.
OWNED = ("DATA_DIR", "PORT", "WATCH_DIR", "STATE_DIR", "VERIFY_FILES_ON_DISK")


def build(addon_options, watch_dir):
    """Returns (environment, warnings). Warnings are for the log; they are not fatal."""
    environment = {
        # Exported even when empty, so an unconfigured add-on fails with upstream's own message
        # naming the variable rather than with something this add-on had to invent.
        "WAHOO_CLIENT_ID": addon_options["wahoo_client_id"],
        "DATA_DIR": str(DATA_DIR),
        "PORT": PORT,
        # Upstream downloads into WATCH_DIR and deduplicates against the history in STATE_DIR, so
        # Dreeve is free to delete what it imports without anything being fetched twice.
        "WATCH_DIR": str(watch_dir),
        "STATE_DIR": str(STATE_DIR),
        "LOG_LEVEL": addon_options["log_level"],
        "WAHOO_REDIRECT_URI": addon_options["redirect_uri"] or FALLBACK_REDIRECT_URI,
    }

    # Omitted rather than exported empty: an empty SYNC_CRON disables upstream's scheduler and an
    # empty SYNC_TIME_WINDOW reads as all_time, so a cleared option must fall back to upstream's
    # default instead of silently meaning something else.
    for option_key, variable in (
        ("wahoo_client_secret", "WAHOO_CLIENT_SECRET"),
        ("sync_time_window", "SYNC_TIME_WINDOW"),
        ("sync_cron", "SYNC_CRON"),
        ("tz", "TZ"),
    ):
        if addon_options[option_key]:
            environment[variable] = addon_options[option_key]

    warnings = []
    for entry in addon_options["extra_env"]:
        key, separator, value = entry.partition("=")
        key = key.strip()
        if not separator or not key:
            warnings.append(
                "Ignoring extra_env entry {0!r}: expected KEY=VALUE.".format(entry)
            )
            continue
        if key in OWNED:
            warnings.append(
                "Ignoring extra_env entry for {0}: this add-on owns that variable.".format(key)
            )
            continue
        if not VARIABLE_NAME.match(key):
            warnings.append(
                "Ignoring extra_env entry {0!r}: {1!r} is not a valid environment variable "
                "name.".format(entry, key)
            )
            continue
        environment[key] = value

    return environment, warnings


def as_shell(environment):
    """Renders the environment as export lines a POSIX shell can source safely."""
    return "".join(
        "export {0}={1}\n".format(key, shlex.quote(value))
        for key, value in sorted(environment.items())
    )
