"""Turns add-on options into an environment file ha-start.sh can source.

Everything that can fail without contacting Garmin fails here, before the connector starts.
"""

from __future__ import annotations

import sys
from pathlib import Path

from dreeve_ha import env, options, secretfile, watchdir

ENV_FILE = Path("/run/dreeve-ha.env")
DATA_DIRS = (env.TOKENS_DIR, env.STATE_DIR)


def run(
    options_file=options.OPTIONS_FILE,
    env_file=ENV_FILE,
    addon_configs=watchdir.ADDON_CONFIGS,
    data_dirs=DATA_DIRS,
    log=print,
):
    addon_options = options.read(options_file)

    try:
        watch_dir = watchdir.resolve(addon_options["watch_dir"], addon_configs=addon_configs)
    except watchdir.WatchDirUnresolvable as exception:
        log("FATAL: {0}".format(exception))
        return 1

    environment, warnings = env.build(addon_options, watch_dir)
    for warning in warnings:
        log("WARN: {0}".format(warning))

    for directory in data_dirs:
        Path(directory).mkdir(parents=True, exist_ok=True)

    # secretfile, not write_text plus chmod: this file carries the Garmin password, so it must never
    # exist at a looser mode, not even for an instant.
    secretfile.write(env_file, env.as_shell(environment).encode("utf-8"))

    log("Delivering Garmin activities into {0}".format(watch_dir))
    return 0


if __name__ == "__main__":
    sys.exit(run())
