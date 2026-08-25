# Dreeve

## Import modes

The add-on supports two import modes, selected via the `import_mode` option:

- `stravaApi` (default): imports activities from the Strava API. Requires `strava_client_id`, `strava_client_secret` and `strava_refresh_token`.
- `files`: imports activities from local `.fit` / `.tcx` / `.gpx` files you drop in the watch dir. Requires no Strava credentials. Set your athlete's first name, last name and gender in the admin panel (Web UI → `/admin`) so imported files can be attributed correctly.

### Providing files over SMB/CIFS (`files` mode)

1. Set `import_mode: files` and `expose_share: true`.
2. The add-on symlinks its file-import watch dir to its mapped config dir, exposed on the host as `/addon_configs/local_statistics_for_strava/watch`.
3. Make that path reachable over SMB/CIFS: in the official Samba add-on, enable the `addon_configs` share. The watch dir then appears under `\\HOST\addon_configs\statistics_for_strava\watch`.
4. Drop `.fit` / `.tcx` / `.gpx` files into that folder.

Notes:

- The daemon scans the watch dir and imports every ~5 minutes; a startup import also runs once per container start.
- Imported files are **deleted** from the watch dir after a successful import — this is expected behavior.
- `expose_share` only controls whether the watch dir is created and symlinked; the underlying mount (`addon_config:rw`) is always granted but scoped to this add-on's own config dir, not all of `/share`.

### Importing from Garmin Connect or Polar Flow (`files` mode)

Provider import is provided by separate connector add-ons in this repository, **Dreeve Garmin
Connector** and **Dreeve Polar Connector**. Each downloads your activities as files into this add-on's
watch folder, which are then imported like any other dropped file.

To use either, configure this add-on with:

- `import_mode: files`
- `expose_share: true` — this puts the watch folder in the add-on config directory, where the
  connector add-ons can write to it

Because `stravaApi` and `files` are mutually exclusive, Strava API import cannot run at the same time
as connector import. Several connectors can run alongside each other, since they all deliver into the
same watch folder.

See each connector add-on's own documentation for setup:

- **Garmin**: uses Garmin's unofficial API, which Garmin neither documents nor supports. Setup covers
  accounts with multi-factor authentication.
- **Polar**: uses Polar's official AccessLink API, which needs a free API client of your own and a
  one-time authorization in the browser. Polar only serves the last 30 days of exercises.

## Add-on options

The add-on options are intentionally minimal — they cover only what the app needs at boot. Everything else (appearance, dashboard layout, metrics, gear, gear maintenance, integrations, the import/build schedule, and so on) is configured **inside the app**, in the built-in admin panel at Web UI → `/admin`.

| Option | Description |
| --- | --- |
| `import_mode` | `stravaApi` or `files`. Default `stravaApi`. See "Import modes" above. |
| `strava_client_id` | OAuth client ID from your Strava API application. Required when `import_mode` is `stravaApi`. |
| `strava_client_secret` | OAuth client secret from your Strava API application. Required when `import_mode` is `stravaApi`. |
| `strava_refresh_token` | Refresh token used to obtain Strava API access tokens. Required when `import_mode` is `stravaApi`. |
| `tz` | Container time zone, e.g. `Europe/Brussels`. |
| `app_url` | The URL you reach the app on (include the port if used). Required — the app will not boot without it. For Home Assistant ingress, a value like `http://localhost:8080` is accepted; set a real, publicly reachable URL if you need direct access or Strava webhooks. |
| `admin_username` | Login user for the admin panel. Default `admin`. |
| `admin_password` | Login password for the admin panel, provided in plaintext here. The add-on hashes it internally into the app's `ADMIN_PASSWORD_HASH`; the plaintext is never stored in the app itself. Required — the admin panel needs a login before it can be used. |
| `dreeve_api_key` | Bearer token for the app's `/api/v1` HTTP API (activity upload, used by GadgetBridge). Optional — leave empty and the API rejects every request. Generate a key in the admin panel under Settings → Security and paste it here. See "The `/api/v1` HTTP API" below. |
| `trust_forwarded_headers` | Whether the app believes `X-Forwarded-*` headers on the direct `8080/tcp` port. Default `false`, which is right unless you put your own reverse proxy in front of that port — see "Direct port access and reverse proxies" below. Ingress is unaffected. |
| `expose_share` | Expose the file-import watch dir over the add-on's mapped config dir (SMB/CIFS) so you can drop activity files into it. Used with `import_mode: files`. |
| `caddy_log_level` | Log verbosity for the embedded web server: `DEBUG`, `INFO`, `WARN`, or `ERROR`. |

You must set `admin_password` before the first start — the add-on fails fast at startup if it is empty, since the admin panel requires a login.

> Privacy note: add-on options are persisted by Home Assistant on disk in `/data/options.json`.
> Do not store unnecessary sensitive personal data in options.

## The `/api/v1` HTTP API

Dreeve v5.3.0 added a small HTTP API — `GET /api/v1/status` and `POST /api/v1/activity/upload`
(multipart, part name `file`) — intended for GadgetBridge and similar clients that push activity
files in. It is off until you set `dreeve_api_key`; without a key every request gets a `401`.

1. Open the admin panel, go to Settings → Security, and generate a key (a `drv_...` value).
2. Paste it into the `dreeve_api_key` add-on option and restart the add-on.
3. Call the API with `Authorization: Bearer drv_...`.

The API is **not reachable through Home Assistant ingress**: ingress requires a Home Assistant
session, so a device client cannot use that URL. Expose the add-on's `8080/tcp` port (Configuration
→ Network) and point the client at `http://<home-assistant-host>:8080/api/v1/...`. The port serves
the whole app, not just the API, so only expose it on a network you trust — or put a reverse proxy
in front of it.

Uploaded files land in the same watch directory the file-import modes use, so they are picked up by
the next import pass.

## Direct port access and reverse proxies

Home Assistant ingress and the optional `8080/tcp` port are served by two separate
listeners inside the add-on. The ingress one is reachable only by the Home Assistant
supervisor; `8080/tcp` is the one you expose. They differ in a single respect: what
they believe about `X-Forwarded-*` request headers.

By default the published port ignores them. It has to: the app trusts any client on a
private network to be a legitimate proxy, so anything on your LAN that can reach the
port could otherwise claim to be one — sending `X-Forwarded-Host` to make the admin
login page redirect somewhere else, or `X-Forwarded-For` to look like an allow-listed
address. Ignoring the headers costs nothing when clients talk to the port directly.

Set `trust_forwarded_headers: true` when the port sits behind **your own** reverse
proxy (nginx, Traefik, Caddy, NPM…) that terminates TLS. Without it the app cannot
see that the original request was HTTPS or which hostname was used, so redirects —
the admin login among them — come back as `http://` and with the add-on's internal
host. Only turn it on when a proxy you control is the only thing that can reach the
port; on a port open to the LAN it hands back exactly the abilities described above.

Serving the app under a **subpath** on your own proxy (e.g. `https://example/dreeve/`)
is not supported on the direct port: the prefix headers are reserved for ingress and
are always stripped there. Use a dedicated hostname, or use ingress.

## Configuring the app

Once the add-on is running, open the Web UI and go to `/admin` to sign in with `admin_username` / `admin_password` and configure everything else: appearance and locale, dashboard layout, metrics, gear and gear maintenance, integrations (AI, notifications, etc.), and the import/build schedule. None of this lives in add-on options anymore.

## Upgrading from Statistics for Strava (v4)

If you are upgrading an existing add-on install from the old YAML-based configuration model:

1. **Back up your data first.** Copy the add-on's `storage/database` and `config` directories before upgrading.
2. **First start migrates your config automatically.** On the first start after upgrading, the app reads your existing `config.yaml` once and copies every setting into its database. From that point on, configure the app in the admin panel (Web UI → `/admin`) — the add-on no longer reads or writes `config.yaml`.
3. **Set an admin password before starting.** Set `admin_password` in the add-on options before the first start after upgrading — the admin panel now requires a login, and startup fails if this is empty.
4. **Set `app_url`.** It is now required and the add-on refuses to start if it is empty. For Home Assistant ingress a value like `http://localhost:8080` is accepted; set a real, publicly reachable URL if you need direct access or Strava webhooks.
5. **Two things are not migrated automatically** and must be redone by hand in the admin panel after the upgrade:
   - **Images referenced from YAML** (gear and gear-maintenance images) — re-upload them.
   - **Gear purchase prices** — re-enter them on the gear pages.

## Runtime model

This add-on runs both required processes inside one container:

- Web UI: `frankenphp` on port `8080`
- Scheduler/daemon: `bin/console app:daemon:run`
- Health endpoint: `GET /healthz` on port `8080` (used by Home Assistant watchdog; returns `503` if required runtime paths are unavailable or the daemon process is not alive; includes a short startup grace period to avoid flapping)
- Static assets (`/assets/*`, `/css/*`, `/js/*`, `/libraries/*`) are served from Symfony `public/`; every page and page fragment is rendered on request by the app itself (Dreeve v5.2.0 dropped pre-built HTML).

## Persistent directories

- `/data/config/app` (holds the legacy `config.yaml` used only for the one-time v4→v5 migration described above)
- `/data/storage/database`
- `/data/storage/files`
- `/data/storage/gear-maintenance`

## Notes

- Home Assistant Ingress is enabled and is the recommended way to access the UI from HA.
- Direct port access via `8080/tcp` remains available for external/reverse-proxy access.
- On startup, the add-on runs database migrations; on first boot this also seeds the database from any legacy `config.yaml` left by a v4 install.
- The recurring activity import is handled automatically by the add-on's built-in daemon — there is nothing to schedule or configure for this.
- Runtime secrets (Strava credentials, the admin password hash, the app secret) are injected via container environment only; no `.env.local` secrets file is written.
- Strava webhooks still require public HTTPS reachability to your webhook endpoint (the Home Assistant ingress URL is not a public webhook endpoint).

For the full application documentation (dashboard configuration, metrics, integrations, and more), see the [Dreeve docs](https://docs.dreeve.app). The upstream project lives at [github.com/dreeveapp/dreeve](https://github.com/dreeveapp/dreeve).
