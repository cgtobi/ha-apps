# Dreeve Wahoo Connector

Imports your Wahoo workouts into [Dreeve](https://github.com/dreeveapp/dreeve).

This add-on runs the upstream
[dreeve-wahoo-connector](https://github.com/dreeveapp/dreeve-wahoo-connector): it lists your workouts
from the Wahoo Cloud API, downloads their `.fit` files and hands them to the Dreeve add-on's watch
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

## Important

Every `.fit` file the connector downloads stays in the add-on's own `/data/downloads`, and the add-on
copies it into Dreeve's watch folder from there. So the add-on's data - and every Home Assistant
snapshot that includes it - grows by roughly 200-500 KB per workout.

That is deliberate. Upstream treats a workout whose file is no longer on disk as never downloaded, and
Dreeve deletes every file it imports. Letting upstream write straight into the watch folder would
therefore re-download the whole sync window on every cycle, forever, so the downloads directory stays
the connector's own and the files are copied out of it.

The add-on is pinned to a `sha-` image tag rather than a version, because this upstream publishes no
releases.

See [DOCS.md](DOCS.md) for setup, including which redirect URI to register with Wahoo and how to
complete the one-time authorization.
