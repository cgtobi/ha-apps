"""Reads the add-on options Home Assistant writes to /data/options.json."""

from __future__ import annotations

import json
from pathlib import Path

OPTIONS_FILE = Path("/data/options.json")

# The defaults also define the shape: a list default means the option is a list of strings, a bool
# default a boolean.
DEFAULTS = {
    "polar_client_id": "",
    "polar_client_secret": "",
    "public_url": "",
    "redirect_uri": "",
    "since": "-30d",
    "tz": "",
    "watch_dir": "",
    "log_level": "info",
    "weight_sync": False,
    "dreeve_api_key": "",
    "dreeve_url": "",
    "weight_unit": "kg",
    "extra_env": [],
}


def read(path=OPTIONS_FILE):
    """Returns every known option, normalised. Unknown keys are dropped, missing ones defaulted."""
    try:
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        raw = {}

    # json.loads happily returns a list, string, number or None, none of which have .get(). Reading
    # a file like that must fall back to defaults rather than crash the add-on at boot.
    if not isinstance(raw, dict):
        raw = {}

    result = {}
    for key, default in DEFAULTS.items():
        value = raw.get(key, default)
        if isinstance(default, bool):
            # Only a real JSON true: the schema says bool, so anything else is a hand-edited file, and
            # "off" is the safe reading of it.
            result[key] = value is True
        elif isinstance(default, list):
            result[key] = [str(item) for item in (value or [])]
        else:
            # Stripping is deliberate and uniform: a pasted value carrying a trailing newline is far
            # more likely than a credential that legitimately starts or ends with whitespace.
            result[key] = str(value if value is not None else "").strip()
    return result
