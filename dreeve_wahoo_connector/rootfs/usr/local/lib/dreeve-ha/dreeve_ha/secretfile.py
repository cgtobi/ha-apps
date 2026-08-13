"""Writes files that hold credentials, at mode 600 from the moment they exist.

Path.write_bytes() followed by chmod() creates the file under the process umask first, leaving a
window where a Wahoo client secret is readable by anyone on the system. os.open with the mode up
front closes that window.
"""

from __future__ import annotations

import os
from pathlib import Path

MODE = 0o600


def write(path, payload):
    """Writes payload (bytes) to path, creating or truncating it at mode 600."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, MODE)
    try:
        os.write(descriptor, payload)
    finally:
        os.close(descriptor)
    # O_CREAT ignores the mode for a file that already existed, so an older looser file is tightened.
    os.chmod(str(path), MODE)
