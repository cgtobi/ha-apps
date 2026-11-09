# Dreeve

## Import modes

The add-on supports two import modes, selected via the `import_mode` option:

- `stravaApi` (default): imports activities from the Strava API. Requires `strava_client_id`, `strava_client_secret` and `strava_refresh_token`.
- `files`: imports activities from local `.fit` / `.tcx` / `.gpx` files you drop in the watch dir. Requires no Strava credentials. Set your athlete's first name, last name and gender in the admin panel (Web UI → `/admin`) so imported files can be attributed correctly.

### Providing files over SMB/CIFS (`files` mode)

1. Set `import_mode: files` and `expose_share: true`.
2. The add-on symlinks its file-import watch dir to its mapped config dir, exposed on the host as `/addon_configs/<prefix>_statistics_for_strava/watch`. `<prefix>` is `local` if you installed the add-on locally, otherwise a short code Home Assistant derives from the add-on repository.
3. Make that path reachable over SMB/CIFS: in the official Samba add-on, enable the `addon_configs` share. The watch dir then appears under `\\HOST\addon_configs\<prefix>_statistics_for_strava\watch`.
4. Drop `.fit` / `.tcx` / `.gpx` files into that folder.

Notes:

- The daemon scans the watch dir and imports every ~5 minutes; a startup import also runs once per container start.
- Imported files are **deleted** from the watch dir after a successful import — this is expected behavior.
- A `.uploads` directory appears inside the watch folder. It is the app's staging area: files uploaded through the admin panel or the API are written there and then moved into place, so an import never sees a half-written file. Leave it alone; it stays empty between uploads.
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

Dreeve v5.3.0 and later refuse a FIT file that contains more than one sport — a triathlon recorded
as a single multi-sport activity, for example — with `Multi-sport FIT file "..." import not
supported, each leg needs to be imported as a separate file`. Export the legs individually from the
device or platform. This is upstream behavior and applies however the file arrives: connector, SMB
drop, or API upload.

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
| `admin_allowed_ips` | Optional comma-separated list of IP addresses or CIDR ranges allowed to reach the admin panel. Empty (the default) means no restriction. See "Restricting the admin panel by IP" below. |
| `dreeve_api_key` | Bearer token for the app's `/api/v1` HTTP API (activity upload, used by GadgetBridge). Optional — leave empty and the API rejects every request. Generate a key in the admin panel under Settings → Security and paste it here. See "The `/api/v1` HTTP API" below. |
| `dreeve_mcp_key` | Bearer token for the app's read-only MCP server at `/mcp`. Optional — leave empty and the MCP server rejects every request. Generate a key in the admin panel under Settings → Security → MCP access and paste it here. See "The MCP server" below. |
| `oidc_issuer_url` | Issuer URL of your OpenID Connect identity provider, for signing in to the admin panel with single sign-on. Optional — single sign-on is on only when all four `oidc_` options are set. See "Single sign-on (OIDC)" below. |
| `oidc_client_id` | Client ID of the client you created for Dreeve at your identity provider. |
| `oidc_client_secret` | Client secret of that client. |
| `oidc_allowed_users` | Who may sign in with single sign-on, one entry per user: their subject (`sub`) at the identity provider, or their verified email address. |
| `oidc_ca_file` | Path to your own CA certificate (PEM) when the identity provider's HTTPS certificate is signed by it, e.g. `/ssl/my-ca.pem`. Optional — leave empty for a provider with a public certificate. See "Identity provider with a private CA" below. |
| `ai_api_key` | API key for the AI workout assistant when it runs on a cloud provider. Optional — a self-hosted `ollama` needs no key, and the assistant is off entirely until you enable it in the admin panel. See "The AI workout assistant" below. |
| `trust_forwarded_headers` | Whether the app believes `X-Forwarded-*` headers on the direct `8080/tcp` port. Default `false`, which is right unless you put your own reverse proxy in front of that port — see "Direct port access and reverse proxies" below. Ingress is unaffected. |
| `expose_share` | Expose the file-import watch dir over the add-on's mapped config dir (SMB/CIFS) so you can drop activity files into it. Used with `import_mode: files`. |
| `caddy_log_level` | Log verbosity for the embedded web server: `DEBUG`, `INFO`, `WARN`, or `ERROR`. |

You must set `admin_password` before the first start — the add-on fails fast at startup if it is empty, since the admin panel requires a login.

> Privacy note: add-on options are persisted by Home Assistant on disk in `/data/options.json`.
> Do not store unnecessary sensitive personal data in options.

## Restricting the admin panel by IP

`admin_allowed_ips` takes a comma-separated list of addresses or CIDR ranges, for example
`192.168.1.50, 192.168.4.0/24`. When it is set, any request for `/admin` from an address not on the
list is answered with `404` — a scanner on your network sees no admin panel rather than a login form.
Leave it empty (the default) and nothing is restricted.

What it does and does not do:

- It gates **only** `/admin` and the pages below it. The dashboard, your activity pages, `/files/*`
  and the `/api/v1` endpoints are unaffected — the API has its own key, the rest is readable by
  anyone who can reach the app.
- It is **not** a login. `admin_password` is still what protects the panel; this only narrows who
  gets to try.
- Home Assistant ingress keeps working whatever you list. The add-on always allows the supervisor
  network (`172.30.32.0/23`) on top of your entries, because the check applies to ingress requests
  too and would otherwise lock you out of the panel in the HA sidebar. Ingress already requires a
  Home Assistant login, so nothing is opened up by that.
- A malformed entry is refused at startup and the option is ignored, with the reason in the add-on
  log — the restriction is simply not applied, rather than the panel becoming unreachable.

> **This option and `trust_forwarded_headers` work against each other.** With
> `trust_forwarded_headers: true` on a port that your LAN can reach, any client there can send an
> `X-Forwarded-For` header naming an allowed address and pass the check. Only combine the two when
> the port is reachable exclusively through a reverse proxy you control.

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

## The MCP server

Dreeve v5.7.0 added a read-only [MCP](https://modelcontextprotocol.io) server at `/mcp`. It lets an
AI client you already use — Claude Code, Claude Desktop, Cursor, VS Code — read your activities,
metrics and settings and answer questions about them. No tool it offers can change anything. It is
off until you set `dreeve_mcp_key`; without a key every request gets a `401`.

1. Open the admin panel, go to Settings → Security → MCP access, and generate a key (a `drvm_...`
   value). It is a separate key from `dreeve_api_key`; neither works in place of the other.
2. Paste it into the `dreeve_mcp_key` add-on option and restart the add-on.
3. Point your client at `http://<home-assistant-host>:8080/mcp` with
   `Authorization: Bearer drvm_...`. For Claude Code:

   ```sh
   claude mcp add --transport http dreeve http://<home-assistant-host>:8080/mcp --header "Authorization: Bearer drvm_..."
   ```

   Other clients: see [Dreeve's MCP documentation](https://docs.dreeve.app/integrations/mcp/).

As with the `/api/v1` API, the MCP server is **not reachable through Home Assistant ingress** — an
MCP client has no Home Assistant session — so it needs the `8080/tcp` port exposed.

Two things to keep in mind:

- **The key is the only access control.** It gives read access to all your data, and
  `admin_allowed_ips` does not apply to `/mcp`. Treat it like a password.
- **`8080/tcp` is plain HTTP.** The key crosses your network unencrypted on every request. That is
  fine on a network you trust; anywhere else, put a reverse proxy terminating TLS in front of the
  port (see "Direct port access and reverse proxies" below).

## Single sign-on (OIDC)

Dreeve v5.8.0 can sign you in to the admin panel through your own OpenID Connect identity provider
(Authentik, Keycloak, Authelia, Pocket ID, …) instead of with the password. The login page then shows
a **Sign in with single sign-on** button. `admin_password` stays required and keeps working next to
it — inside Home Assistant it is the only way in, and it is your way back in when the identity
provider is down.

**It only works on the `8080/tcp` port, not through ingress.** The identity provider only sends you
back to a callback URL registered with it beforehand, and Dreeve builds that URL from the address you
opened the app on. Under ingress that address carries a token that changes with every Home Assistant
session, so no registration can match it. Clicking the button inside Home Assistant shows a short
explanation instead.

1. Expose the add-on's `8080/tcp` port (Configuration → Network). If your identity provider insists on
   `https` callback URLs, as many do, put your own reverse proxy terminating TLS in front of it and set
   `trust_forwarded_headers: true` — see "Direct port access and reverse proxies" below.
2. At the identity provider, create a confidential OpenID Connect client (authorization code flow,
   with a client secret) and register this callback URL, exactly as Dreeve will send it:
   - port opened directly: `http://<home-assistant-host>:8080/admin/login/oidc/callback`
   - behind your reverse proxy: `https://<your-hostname>/admin/login/oidc/callback`
3. Fill in `oidc_issuer_url`, `oidc_client_id`, `oidc_client_secret` and `oidc_allowed_users`, then
   restart the add-on. The log says `Single sign-on enabled` once all four are set, or names the ones
   that are missing.
4. Open the admin panel **on the address from step 2** and check Settings → Security → Single sign-on.
   The **Redirect URI** shown there is the callback URL Dreeve sends; it must match the registered one
   character for character. (Read through ingress, that page shows the ingress address instead, which
   is not the one to register.)

Good to know:

- `oidc_allowed_users` takes one user per entry: the user's subject (`sub`) at the identity provider,
  or their email address. An email only counts when the provider marks it as verified. Anyone not
  listed is turned away after signing in at the provider.
- Dreeve asks for the scopes `openid email profile`, uses PKCE, authenticates at the token endpoint
  with HTTP Basic (`client_secret_basic`), and accepts only asymmetrically signed ID tokens (RS256,
  ES256 and the like). A provider that signs with a shared secret (HS256) is rejected.
- The add-on itself must reach the issuer URL — it reads the provider's discovery document, exchanges
  the login code and fetches the signing keys from there. An identity provider only reachable from
  your browser will not do.
- `admin_allowed_ips` still applies: the callback is part of `/admin`, so your browser's address must
  be allowed.
- **Authelia** leaves `email` out of the ID token by default, and Dreeve reads the user from the ID
  token only. To allow users by email address, give the client a claims policy that puts it back:

  ```yaml
  identity_providers:
    oidc:
      claims_policies:
        dreeve:
          id_token: ['email', 'email_verified', 'preferred_username', 'name']
      clients:
        - client_id: 'dreeve'
          claims_policy: 'dreeve'
          # ...the rest of the client as before
  ```

  Without it, only the subject (`sub`) entries in `oidc_allowed_users` can ever match.
- When a sign-in fails, where to look depends on what you see:
  - **An error page with a `Reference:` code, right after clicking the button.** The add-on could not
    reach the identity provider, or did not trust its certificate (see "Identity provider with a
    private CA" below). The add-on log has the cause in an `errors.ERROR: <reference> - GET
    /admin/login/oidc - ...` entry.
  - **"Single sign-on failed, see errors.log for details", "Your sign-in session expired" or "The
    provider returned an error".** It failed on the way back from the provider. The add-on log has
    the reason in an `errors.ERROR: OIDC login failed - ...` line. The "errors.log" the message
    mentions holds the same entries; it sits under `/data/storage/files/logs/` inside the add-on,
    which Home Assistant does not let you open.
  - **"You are not allowed to sign in to this admin panel."** You signed in at the provider, but no
    `oidc_allowed_users` entry matched. Nothing is logged for this. Compare the entries with your
    subject (`sub`) and verified email at the provider, and with Authelia check the claims policy
    above.

### Identity provider with a private CA

If your identity provider's HTTPS certificate is signed by your own certificate authority (common
with a home-lab CA, or step-ca), the add-on cannot verify it: clicking **Sign in with single
sign-on** ends on an error page with a `Reference:` code, and the add-on log shows a certificate
error under that reference. Give the add-on the CA certificate:

1. Put the CA certificate, in PEM format (the text file starting with `-----BEGIN CERTIFICATE-----`),
   into Home Assistant's `ssl` folder, for example as `my-ca.pem`. The add-on's own config folder
   (`/addon_configs/<prefix>_statistics_for_strava` on the host, see "Providing files over SMB/CIFS")
   works as well.
2. Set `oidc_ca_file` to its path **as the add-on sees it**: `/ssl/my-ca.pem`, or `/config/my-ca.pem`
   for the add-on's config folder. Restart the add-on.

The log confirms the file when single sign-on starts up, or says why it was ignored (no such file,
no certificate in it, single sign-on off). Dreeve then trusts **only** the certificates in that file for requests to the
identity provider, not the usual public CAs, so leave the option empty for a provider with a public
certificate (Let's Encrypt and the like). If the provider's certificate comes from an intermediate
CA, the file can hold several certificates one after another.

## The AI workout assistant

Dreeve can hand your activity data to an LLM and let you ask it questions. Which provider and model
to use, whether the chat appears in the UI at all, and any custom chat commands are configured
**inside the app**, in the admin panel under Settings → Integrations. `ai_api_key` is the one piece
of that configuration the app reads from its environment instead, which is why it is an add-on
option.

1. Put your provider's key in `ai_api_key` and restart the add-on. Leave it empty for `ollama`,
   which takes no key.
2. In the admin panel, go to Settings → Integrations, choose the provider and model, and turn the
   assistant's UI on.
3. Open the Web UI and pick **Workout assistant** from the profile menu, top right.

Worth knowing:

- **Save the settings with `ai_api_key` empty and a cloud provider selected and the app refuses,
  with "API key cannot be empty".** That is the intended signal that the option is not set yet.
- **The assistant is served through Home Assistant ingress only.** Its pages take no login of their
  own — unlike `/admin` and `/api/v1`, the app does not gate them — and its tools can read your
  activities, gear and athlete details while every message spends your API credits. Ingress puts a
  Home Assistant login in front of that; the direct `8080/tcp` port would not, so the add-on answers
  `404` there. The profile menu still lists the entry when you browse that port, because that menu
  comes from the app and the app does not know; the link lands on a "not found" page.
- **A self-hosted `ollama` is not on `localhost` from the add-on's point of view.** Inside the
  container that address is the container itself. Use the Home Assistant host's LAN address
  (`http://192.168.1.10:11434/api`), or, if `ollama` runs as another add-on, its name on the
  Supervisor network.
- **The key is shown in plaintext** in the admin panel's Integrations page, in a disabled field, and
  is stored in `/data/options.json` like every other option.


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

Once the add-on is running, open the Web UI and go to `/admin` to sign in with `admin_username` / `admin_password` and configure everything else: appearance and locale, dashboard layout, metrics, gear and gear maintenance, integrations (AI, notifications, etc.), and the import/build schedule. Apart from the three keys above — `dreeve_api_key`, `dreeve_mcp_key` and `ai_api_key`, which the app reads from its environment — none of this lives in add-on options anymore.

## Upgrading from Statistics for Strava (v4)

If you are upgrading an existing add-on install from the old YAML-based configuration model:

1. **Back up your data first.** Copy the add-on's `storage/database` and `config` directories before upgrading.
2. **First start migrates your config automatically.** On the first start after upgrading, the app reads your existing `config.yaml` once and copies every setting into its database. From that point on, configure the app in the admin panel (Web UI → `/admin`) — the add-on no longer reads or writes `config.yaml`.
3. **Set an admin password before starting.** Set `admin_password` in the add-on options before the first start after upgrading — the admin panel now requires a login, and startup fails if this is empty.
4. **Set `app_url`.** It is now required and the add-on refuses to start if it is empty. For Home Assistant ingress a value like `http://localhost:8080` is accepted; set a real, publicly reachable URL if you need direct access or Strava webhooks.
5. **Two things are not migrated automatically** and must be redone by hand in the admin panel after the upgrade:
   - **Images referenced from YAML** (gear and gear-maintenance images) — re-upload them.
   - **Gear purchase prices** — re-enter them on the gear pages.

## Skipped updates

Dreeve occasionally rewrites its database migration history ("squashes" it). A release that has done so can only migrate a database that came through the release right before the squash — Dreeve v5.3.3, in the case of v5.4.0. Home Assistant always updates an add-on straight to the newest version, so it cannot be asked to stop at an intermediate one; the add-on deals with this itself.

- **Normally you notice nothing.** If your database is behind, the add-on replays the missing migrations from the previous Dreeve version, which it carries for exactly this purpose, and then starts as usual. The log says so.
- **If the database is too old for that**, the add-on stops before the app starts, leaves the database untouched, and serves a page with instructions instead of the dashboard (the same instructions go to the log). You then reinstall the add-on version named there — restore a backup of it, or roll back — start it once so its migrations run, and update again.

Take a Home Assistant backup before updating the add-on. It is what makes the roll-back above a one-click affair, and it is worth having for any update that touches the database.

## Runtime model

This add-on runs both required processes inside one container:

- Web UI: `frankenphp` on port `8080`
- Scheduler/daemon: `bin/console app:daemon:run`
- Health endpoint: `GET /healthz` on port `8080` (used by Home Assistant watchdog; returns `503` if required runtime paths are unavailable or the daemon process is not alive; includes a short startup grace period to avoid flapping)
- Static assets (`/assets/*`, `/css/*`, `/js/*`, `/libraries/*`) are served from Symfony `public/`; every page is rendered on request by the app itself (Dreeve v5.2.0 dropped pre-built HTML).

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
- Dreeve's own "new version available" notice is switched off. It announces upstream releases, which reach you only once a new add-on version ships them; Home Assistant tells you about that one.

For the full application documentation (dashboard configuration, metrics, integrations, and more), see the [Dreeve docs](https://docs.dreeve.app). The upstream project lives at [github.com/dreeveapp/dreeve](https://github.com/dreeveapp/dreeve).
