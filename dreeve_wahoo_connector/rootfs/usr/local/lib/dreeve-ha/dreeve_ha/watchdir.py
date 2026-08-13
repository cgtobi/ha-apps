"""Finds the Dreeve watch folder this connector delivers into.

The Dreeve add-on's slug carries an install-dependent prefix - `local_` for a local add-on,
a repository hash otherwise - so the folder is matched by suffix rather than named outright.
"""

from __future__ import annotations

import os
from pathlib import Path

ADDON_CONFIGS = Path("/addon_configs")
DREEVE_GLOB = "*statistics_for_strava"


class WatchDirUnresolvable(Exception):
    """Nothing to deliver into, or too many candidates to choose between."""


def _checked(watch_dir):
    """The connector can only report a delivery failure per cycle; catching it here is far clearer."""
    if not watch_dir.is_dir():
        raise WatchDirUnresolvable(
            "The watch folder {0} does not exist. Check the 'watch_dir' option, or leave it empty to "
            "auto-detect the Dreeve add-on's own folder.".format(watch_dir)
        )
    if not os.access(str(watch_dir), os.W_OK):
        raise WatchDirUnresolvable(
            "The watch folder {0} is not writable, so workouts cannot be delivered into "
            "it.".format(watch_dir)
        )
    return watch_dir


def resolve(configured, addon_configs=ADDON_CONFIGS):
    """Returns the watch folder: the configured one when set, otherwise the single auto-detected one."""
    if configured:
        return _checked(Path(configured))

    addon_configs = Path(addon_configs)
    # is_dir() also filters out a matching name that is a file, and a slug directory whose "watch" is
    # a file. It reports an unreadable directory as absent too, so a permission problem surfaces as
    # "not found" - unlikely here, since both add-ons run as root.
    candidates = sorted(
        watch for watch in (candidate / "watch" for candidate in addon_configs.glob(DREEVE_GLOB))
        if watch.is_dir()
    )

    if not candidates:
        raise WatchDirUnresolvable(
            "No Dreeve watch folder found under {0}/{1}/watch, where '*' stands for the Dreeve "
            "add-on's install-specific slug prefix. Enable 'expose_share' in the Dreeve add-on and "
            "start it once, or set this add-on's 'watch_dir' option.".format(
                addon_configs, DREEVE_GLOB
            )
        )

    if len(candidates) > 1:
        found = ", ".join(str(candidate) for candidate in candidates)
        raise WatchDirUnresolvable(
            "Several Dreeve watch folders found ({0}). Set this add-on's 'watch_dir' option to "
            "pick one.".format(found)
        )

    return _checked(candidates[0])
