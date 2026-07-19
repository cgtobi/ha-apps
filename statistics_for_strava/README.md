# Home Assistant Add-on: Dreeve

Single-container Home Assistant add-on for [Dreeve](https://github.com/dreeveapp/dreeve), a self-hosted dashboard for your sports & fitness data, with:

- Home Assistant Ingress support (streaming enabled for SSE)
- direct web UI on configurable host port mapping for internal `8080/tcp`
- internal daemon for scheduled imports, dashboard builds and webhooks
- watchdog health check endpoint at `/healthz`
- persistent `/data` mapping for the database, storage, and build output

Strava is optional: import activities from the Strava API (`import_mode: stravaApi`, the default) or from local `.fit`/`.tcx`/`.gpx` activity files you drop in a watch dir (`import_mode: files`), with no Strava account required.

Add-on options only cover what the app needs at boot — import mode, Strava credentials, time zone, app URL, and the admin panel login. Everything else (appearance, dashboard layout, metrics, gear, integrations, and the import schedule) is configured in the app itself, in the built-in admin panel at Web UI → `/admin`. Set an admin password in the add-on options before the first start; the admin panel requires a login.

Privacy note: add-on options are persisted by Home Assistant on disk in `/data/options.json`.
Avoid storing unnecessary sensitive personal data in options.

Runtime secrets are provided via container environment (no `.env.local` secret file).

See [DOCS.md](DOCS.md) for the full list of add-on options, import modes, and upgrading from Statistics for Strava (v4). Full application documentation lives at [docs.dreeve.app](https://docs.dreeve.app).
