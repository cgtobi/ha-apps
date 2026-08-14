"""Turns add-on options into an environment file ha-start.sh can source.

Everything that can fail without contacting Wahoo fails here, before the connector starts.
"""

from __future__ import annotations

import sys
from pathlib import Path

from dreeve_ha import env, options, secretfile, watchdir

ENV_FILE = Path("/run/dreeve-ha.env")
# /data/state carries everything that has to outlive a restart: the Wahoo tokens, the sync history
# upstream deduplicates against, and the certificate it generates for an https redirect. Upstream
# creates it too, but only when it first reads there - and a failure that late is a traceback from a
# background thread rather than a line from the add-on's own startup.
DATA_DIRS = (env.STATE_DIR,)


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

    if not addon_options["redirect_uri"]:
        # Not fatal: the dashboard still comes up, and a user who has not created a Wahoo application
        # yet has nothing to put here. But no authorization can complete until it matches the URL
        # registered with that application, so the option is worth naming outright.
        log(
            "NOTE: 'redirect_uri' is not set, so nobody can authorize yet. Register "
            "http://<home-assistant-host>:8085/callback with your application at "
            "developers.wahooligan.com, then set 'redirect_uri' to that exact URL."
        )
    elif addon_options["redirect_uri"].startswith("https://"):
        # Also not fatal, and sometimes the only thing Wahoo's portal accepts. But upstream reacts
        # to an https redirect by generating a self-signed certificate and serving the dashboard
        # over TLS, after which the add-on's http:// webui link answers nothing at all - a dead OPEN
        # WEB UI button that names no cause. The status loop pays for it too, spending a failed http
        # attempt every cycle before it retries over https.
        log(
            "NOTE: 'redirect_uri' uses https://, so the connector serves the dashboard over TLS "
            "with a self-signed certificate. The add-on's OPEN WEB UI link is http:// and will not "
            "work; open the dashboard with https:// by hand and accept the certificate warning."
        )

    for directory in data_dirs:
        Path(directory).mkdir(parents=True, exist_ok=True)

    # secretfile, not write_text plus chmod: this file carries the Wahoo client secret, so it must
    # never exist at a looser mode, not even for an instant.
    secretfile.write(env_file, env.as_shell(environment).encode("utf-8"))

    log("Delivering Wahoo workouts into {0}".format(watch_dir))
    return 0


if __name__ == "__main__":
    sys.exit(run())
