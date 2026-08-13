"""Builds the environment the upstream connector reads at startup.

There is no add-on login step: Wahoo authorization is an OAuth redirect the connector's own dashboard
serves on PORT. That port is owned by the add-on - moving it would take away the dashboard, the
watchdog's only signal and the published host port in one go.

DATA_DIR is owned for a second reason. Upstream keeps every file it has downloaded under
$DATA_DIR/downloads and asks whether that exact file still exists before deciding a workout was
already fetched, while Dreeve deletes what it imports. So upstream is never pointed at the watch
folder; dreeve_ha.relay copies out of the downloads directory instead, and DREEVE_WATCH_DIR here is
read by that relay rather than by upstream, which has no way of being told where to write.
"""

from __future__ import annotations

import re
import shlex
from pathlib import Path

DATA_DIR = Path("/data")
DOWNLOADS_DIR = DATA_DIR / "downloads"
STATE_DIR = DATA_DIR / "state"
# Bound on all interfaces by upstream (app.run(host="0.0.0.0")): the TCP watchdog reaches it over the
# container's own address, and the `ports` entry in config.yaml publishes it on the host so a browser
# can complete the authorization.
PORT = "8080"
# Upstream's own fallback is https://localhost:8085/callback, and any https redirect turns on a
# self-signed certificate, so an unconfigured add-on would answer its webui link with a certificate
# warning. This keeps the dashboard on plain HTTP; a login attempt then fails on Wahoo's own redirect
# mismatch, which names the actual problem.
FALLBACK_REDIRECT_URI = "http://localhost:8080/callback"

# A key that is not a valid shell variable name would render an export line the entrypoint cannot
# source, taking the whole add-on down with a syntax error that names no option.
VARIABLE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# Overriding these would break persistence and the token store (DATA_DIR), the dashboard, the
# watchdog and the published port (PORT), or the relay's delivery target (DREEVE_WATCH_DIR).
# WATCH_DIR is owned although nothing here exports it: it is the name a planned upstream change will
# make upstream honour, and letting a user hand-activate that support behind the relay's back would
# have upstream write into the folder Dreeve empties, which it then re-downloads in full every cron
# fire. USE_HTTPS is deliberately absent: it is the documented way out when Wahoo refuses a
# plain-HTTP redirect.
OWNED = ("DATA_DIR", "PORT", "WATCH_DIR", "DREEVE_WATCH_DIR")


def build(addon_options, watch_dir):
    """Returns (environment, warnings). Warnings are for the log; they are not fatal."""
    environment = {
        # Exported even when empty, so an unconfigured add-on fails with upstream's own message
        # naming the variable rather than with something this add-on had to invent.
        "WAHOO_CLIENT_ID": addon_options["wahoo_client_id"],
        "DATA_DIR": str(DATA_DIR),
        "PORT": PORT,
        # Read by dreeve_ha.relay, and deliberately not named WATCH_DIR: a planned upstream change
        # gives that name to upstream itself, so the first bump onto such a build would have it
        # write straight into the folder Dreeve empties - and since its deduplication asks whether
        # the file is still on disk, it would re-download its whole window every cron fire.
        "DREEVE_WATCH_DIR": str(watch_dir),
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
