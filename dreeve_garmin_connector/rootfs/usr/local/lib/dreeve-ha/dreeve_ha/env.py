"""Builds the environment the upstream connector reads at startup.

ALLOW_PASSWORD_LOGIN is deliberately never set: the daemon must not log in on its own, because
repeated logins are what get a Garmin account rate-limited. dreeve_ha.login owns that, once, at boot.
"""

from __future__ import annotations

import re
import shlex
from pathlib import Path

TOKENS_DIR = Path("/data/tokens")
STATE_DIR = Path("/data/state")
# Bound on all interfaces so the add-on's TCP watchdog can reach it; no `ports` entry publishes it.
STATUS_ADDR = "0.0.0.0:8080"

# A key that is not a valid shell variable name would render an export line the entrypoint cannot
# source, taking the whole add-on down with a syntax error that names no option.
VARIABLE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# Overriding these would break persistence (the first three) or the watchdog (the fourth).
OWNED = ("GARMINTOKENS", "STATE_DIR", "WATCH_DIR", "HTTP_ADDR")


def build(addon_options, watch_dir):
    """Returns (environment, warnings). Warnings are for the log; they are not fatal."""
    environment = {
        "GARMIN_EMAIL": addon_options["garmin_email"],
        "GARMINTOKENS": str(TOKENS_DIR),
        "STATE_DIR": str(STATE_DIR),
        "WATCH_DIR": str(watch_dir),
        "HTTP_ADDR": STATUS_ADDR,
        "LOG_LEVEL": addon_options["log_level"],
    }

    for option_key, variable in (
        ("garmin_password", "GARMIN_PASSWORD"),
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
