# Dreeve Polar Connector

Imports your Polar Flow training sessions into [Dreeve](https://github.com/dreeveapp/dreeve).

This add-on runs the upstream
[dreeve-polar-connector](https://github.com/dreeveapp/dreeve-polar-connector): it lists new Polar
exercises, downloads their `.fit` files (falling back to `.tcx` where Polar has no FIT) and drops
them into the Dreeve add-on's watch folder, which Dreeve then imports on its usual schedule.

## Requirements

The Dreeve add-on must be installed and configured with:

- `import_mode: files`
- `expose_share: true`

Polar sessions arrive as files, and Dreeve's `stravaApi` and `files` import modes are mutually
exclusive - so Strava API import cannot run at the same time as Polar.

You also need your own Polar API client, created for free at
[admin.polaraccesslink.com](https://admin.polaraccesslink.com), and a browser to authorize it once.

## Important

Polar's AccessLink API only returns exercises uploaded in the **last 30 days**, and only those
uploaded **after** you authorize this connector. Older history cannot be backfilled through the API;
export it from Polar Flow and drop the files into Dreeve's watch folder by hand.

See [DOCS.md](DOCS.md) for setup, including which redirect URL to register with Polar and how to reach
the one-time authorization page.
