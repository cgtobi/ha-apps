"""Console entrypoint for the login step, kept separate from the importable module for testability."""

from __future__ import annotations

import logging
import sys

from garminconnect import Garmin

from dreeve_ha import login, options


def main():
    logging.basicConfig(
        stream=sys.stdout, level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s"
    )
    try:
        login.ensure_session(options.read(), garmin_factory=Garmin)
    except login.LoginBlocked as exception:
        logging.getLogger("dreeve-ha.login").warning("%s", exception)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
