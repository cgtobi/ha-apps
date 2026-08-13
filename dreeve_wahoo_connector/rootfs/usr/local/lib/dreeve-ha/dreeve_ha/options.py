"""Reads the add-on options Home Assistant writes to /data/options.json."""

from __future__ import annotations

import json
from pathlib import Path

OPTIONS_FILE = Path("/data/options.json")

# The defaults also define the shape: a list default means the option is a list of strings.
#
# There is no log_level: upstream calls logging.basicConfig(level=logging.INFO) with no environment
# override, so the option would promise something nothing reads. It arrives when upstream's LOG_LEVEL
# does.
DEFAULTS = {
    "wahoo_client_id": "",
    "wahoo_client_secret": "",
    "redirect_uri": "",
    "sync_time_window": "1_week",
    "sync_cron": "0 * * * *",
    "tz": "",
    "watch_dir": "",
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
        if isinstance(default, list):
            result[key] = [str(item) for item in (value or [])]
        else:
            # Stripping is deliberate and uniform: a pasted value carrying a trailing newline is far
            # more likely than a credential that legitimately starts or ends with whitespace.
            result[key] = str(value if value is not None else "").strip()
    return result
