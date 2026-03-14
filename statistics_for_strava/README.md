# Home Assistant Add-on: Statistics for Strava

Single-container Home Assistant add-on draft for `statistics-for-strava` with:

- direct web UI on configurable host port mapping for internal `8080/tcp`
- internal daemon scheduling/webhooks process
- watchdog health check endpoint at `/healthz`
- persistent `/data` mapping for config, DB, files, and build output

Privacy note: add-on options are persisted by Home Assistant on disk in `/data/options.json`.
Avoid storing unnecessary sensitive personal data in options.

Startup validates required Strava options (`strava_client_id`, `strava_client_secret`, `strava_refresh_token`, `tz`) and fails fast if any are empty.

Runtime secrets are provided via container environment (no `.env.local` secret file).

On each config reconciliation invocation, the add-on automatically runs `app:strava:build-files` so UI-config overrides are applied.
`general.appUrl` can now be set via add-on option `general_app_url` (absolute URL).

Historical challenges/trophies can be imported by pasting trophy-case HTML into `strava_challenge_history_html` (Strava page language must be English). See the [docs](https://statistics-for-strava-docs.robiningelbrecht.be/#/getting-started/challenges-and-trophies?id=new-challenges)
