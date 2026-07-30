"""Builds the environment the upstream connector reads at startup.

There is no add-on login step to keep out of the daemon's way here: Polar authorization is an OAuth
redirect the connector serves itself, on HTTP_ADDR. That address is therefore owned by the add-on -
turning it off would remove the only way to authorize as well as the watchdog's only signal.
"""

from __future__ import annotations

import re
import shlex
from pathlib import Path

TOKENS_DIR = Path("/data/tokens")
STATE_DIR = Path("/data/state")
# Bound on all interfaces: the TCP watchdog reaches it over the container's own address, and the
# `ports` entry in config.yaml publishes it on the host so a browser can complete /authorize.
STATUS_ADDR = "0.0.0.0:8080"

# A key that is not a valid shell variable name would render an export line the entrypoint cannot
# source, taking the whole add-on down with a syntax error that names no option.
VARIABLE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# Overriding these would break persistence (the first three) or both the watchdog and the
# authorization page (the fourth).
OWNED = ("POLAR_TOKENS", "STATE_DIR", "WATCH_DIR", "HTTP_ADDR")


def build(addon_options, watch_dir):
    """Returns (environment, warnings). Warnings are for the log; they are not fatal."""
    environment = {
        # Exported even when empty, so an unconfigured add-on fails with upstream's own message
        # naming the variable rather than with something this add-on had to invent.
        "POLAR_CLIENT_ID": addon_options["polar_client_id"],
        "POLAR_TOKENS": str(TOKENS_DIR),
        "STATE_DIR": str(STATE_DIR),
        "WATCH_DIR": str(watch_dir),
        "HTTP_ADDR": STATUS_ADDR,
        "LOG_LEVEL": addon_options["log_level"],
    }

    # The secret is omitted when blank rather than exported empty, which leaves upstream's
    # POLAR_CLIENT_SECRET_FILE convention usable through extra_env - it refuses to accept both.
    for option_key, variable in (
        ("polar_client_secret", "POLAR_CLIENT_SECRET"),
        ("public_url", "PUBLIC_URL"),
        # Sent to Polar verbatim, overriding <public_url>/callback. Polar's admin page accepts a path
        # but its authorization endpoint may then honour only the bare origin, and it compares the
        # value byte for byte - so this is passed through exactly as typed.
        ("redirect_uri", "REDIRECT_URI"),
        ("since", "SINCE"),
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
