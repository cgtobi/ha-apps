# Dreeve Wahoo Connector

Imports your Wahoo workouts into [Dreeve](https://github.com/dreeveapp/dreeve).

This add-on runs the upstream
[dreeve-wahoo-connector](https://github.com/dreeveapp/dreeve-wahoo-connector): it lists your workouts
from the Wahoo Cloud API and downloads their `.fit` files directly into the Dreeve add-on's watch
folder, which Dreeve then imports on its usual schedule.

## Requirements

The Dreeve add-on must be installed and configured with:

- `import_mode: files`
- `expose_share: true`

Wahoo workouts arrive as files, and Dreeve's `stravaApi` and `files` import modes are mutually
exclusive - so Strava API import cannot run at the same time as Wahoo.

You also need your own Wahoo application, created for free at
[developers.wahooligan.com](https://developers.wahooligan.com/applications), and one browser round trip
to authorize it.

This add-on is `amd64` only, because upstream publishes a linux/amd64 image and nothing else. It does
not appear on ARM Home Assistant hosts.

## How delivery works

The connector writes each `.fit` file straight into Dreeve's watch folder: upstream honours
`WATCH_DIR`, and the add-on points it at the folder it resolved. Nothing is copied afterwards, so a
workout is available to Dreeve the moment it has been downloaded, and no workout is stored twice. The
add-on's own data stays small - `/data/state` holds the Wahoo tokens, the sync history and, with an
`https` redirect, the certificate upstream generates.

That works because upstream deduplicates against the sync history alone. Dreeve deletes every file it
imports, and a workout recorded in the history is not fetched again regardless. The one setting that
would undo it is `VERIFY_FILES_ON_DISK`, which restores upstream's older "is the file still there?"
check - never true under Dreeve, so it would re-download the whole sync window on every cycle. The
add-on refuses it from `extra_env` for that reason.

The add-on is pinned to a `sha-` image tag rather than a version, because this upstream publishes no
releases.

See [DOCS.md](DOCS.md) for setup, including which redirect URI to register with Wahoo and how to
complete the one-time authorization.
