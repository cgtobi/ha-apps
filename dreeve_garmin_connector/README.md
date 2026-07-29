# Dreeve Garmin Connector

Imports your Garmin Connect activities into [Dreeve](https://github.com/dreeveapp/dreeve).

This add-on runs the upstream
[dreeve-garmin-connector](https://github.com/dreeveapp/dreeve-garmin-connector): it lists new Garmin
activities, downloads their original `.fit` files and drops them into the Dreeve add-on's watch
folder, which Dreeve then imports on its usual schedule.

## Requirements

The Dreeve add-on must be installed and configured with:

- `import_mode: files`
- `expose_share: true`

Garmin activities arrive as files, and Dreeve's `stravaApi` and `files` import modes are mutually
exclusive - so Strava API import cannot run at the same time as Garmin.

## Important

This uses Garmin's unofficial API, which Garmin neither documents nor supports and has changed
before. Occasional breakage is expected; the fix is usually a newer connector version.

See [DOCS.md](DOCS.md) for setup, including accounts with multi-factor authentication.
