# Dreeve Polar Connector

## Setup

1. Install and start the Dreeve add-on with `import_mode: files` and `expose_share: true`. This puts
   its watch folder where this add-on can write to it.
2. Create a client at [admin.polaraccesslink.com](https://admin.polaraccesslink.com) and register
   `http://<home-assistant-host>:8080/callback` as its redirect URL - the same host you reach Home
   Assistant on, with port 8080.
3. Put the client's ID and secret in `polar_client_id` and `polar_client_secret`, and set
   `public_url` to `http://<home-assistant-host>:8080` (no trailing slash, no `/callback`).
4. Start the add-on and open `http://<home-assistant-host>:8080/authorize` in a browser, then approve
   access at Polar. Syncing starts immediately. The add-on log prints that exact URL, and the add-on
   page's **OPEN WEB UI** button opens it too — when the button is missing, see below.

Until step 4 the add-on log reports `authorization=required` and nothing is delivered. That is
expected, not a failure.

**No OPEN WEB UI button?** Home Assistant builds it from the host port published for 8080, taken from
the add-on's **Configuration → Network** panel. If that field is empty the button disappears. Fill it
in with `8080` and restart, or just open the URL above by hand — the button is only a shortcut.

**Open `/authorize`, never `/callback`.** `/callback` is where Polar sends the browser back, carrying a
`code` and the `state` that `/authorize` issued. Opening it yourself produces *"The state parameter is
missing, unknown or expired"*, which is the connector refusing an unsolicited callback rather than a
misconfiguration.

**Changed the host port?** Everything must agree: the port in **Network**, the `public_url` option, and
the redirect URL registered with your Polar client. Polar rejects any redirect URI that is not
registered verbatim, so remapping 8080 to, say, 8180 means registering
`http://<home-assistant-host>:8180/callback` at Polar as well.

The token Polar issues does not expire and lives in the add-on's own data directory, so this is a
one-time exercise. You may clear `polar_client_secret` afterwards, at the cost of having to set it
again if you ever re-authorize.

## Options

| Option | Default | Meaning |
|---|---|---|
| `polar_client_id` | - | **Required.** From your client at admin.polaraccesslink.com. |
| `polar_client_secret` | - | **Required** to authorize. |
| `public_url` | - | Where this add-on is reachable in a browser, e.g. `http://homeassistant.local:8080`. Builds the OAuth redirect URL, which must match one registered with your Polar client. |
| `since` | `-30d` | How far back the **first** run reaches: a date (`2026-07-01`), an offset (`-30d`, `720h`) or `now`. Polar keeps 30 days, so `-30d` is everything there is. Ignored afterwards. |
| `tz` | `Etc/GMT` | Timezone for log timestamps and date comparisons. |
| `watch_dir` | - | Leave empty to auto-detect the Dreeve add-on's watch folder. Set it if auto-detection reports several candidates. |
| `log_level` | `info` | `debug`, `info`, `warning`, `error` or `critical`. |
| `extra_env` | `[]` | Extra connector settings as `KEY=VALUE`, for example `SPORTS=running,cycling` or `POLL_INTERVAL=1800`. |

`extra_env` cannot set `POLAR_TOKENS`, `STATE_DIR`, `WATCH_DIR` or `HTTP_ADDR`: the add-on owns
those, and overriding them would break persistence, the authorization page or the watchdog. Attempts
are logged and ignored.

Useful `extra_env` settings: `SPORTS` (only these sports), `FALLBACK_FORMAT` (`tcx`, `gpx` or `none`
for exercises without a FIT file), `ON_CONFLICT`, `POLL_INTERVAL`, `MAX_DOWNLOADS_PER_CYCLE`,
`WEBHOOK_URL`, `PUID`/`PGID`.

`public_url` may be left empty if - and only if - your Polar client has exactly one registered
redirect URL, which Polar then uses automatically. With several registered, authorization fails until
you set it.

## Why authorization uses a port and not ingress

Polar redirects the browser back to a URL registered with your client beforehand. Home Assistant's
ingress URL contains a session token that changes whenever the add-on restarts, so it can never be
registered. The add-on therefore publishes port 8080 on the host, and `/authorize` is served there.

If port 8080 is already taken on your Home Assistant host, change the add-on's port mapping in the
add-on's **Network** panel, and register the new port's `/callback` with Polar instead.

## Reading the log

One line is logged whenever the connector's status changes:

```
healthy=True authorization=ok authorizeUrl=None backlog=42 lastSuccessfulSync=... nextRunAt=... backoffSeconds=0 lastError=None
```

- `authorization=required` means nobody has authorized yet. `authorizeUrl` is the URL to open, and it
  is `None` once authorized.
- `authorization=revoked` means Polar refused the stored token. Authorize again; the next cycle picks
  the new token up without a restart.
- `backlog` is the number of exercises still owed a download.
- `backoffSeconds` above zero means Polar rate-limited the connector and it is waiting.
- The connector also logs `docker compose run --rm polar-connector login` in some situations.
  **Ignore that.** It is written for Docker Compose users; on Home Assistant, use the Web UI.

## Pace

A cycle lists exercises and downloads at most 25 of them, every 15 minutes by default. Polar's
published budget is 520 requests per 15 minutes for one user, so this uses a small fraction of it. A
first run with a full 30 days therefore backfills over a few cycles rather than at once; the log
reports the remaining `backlog` whenever it changes.

## Instant delivery (optional)

Set `WEBHOOK_URL` in `extra_env` to a publicly reachable **HTTPS** URL ending in `/webhook` that
forwards to this add-on, and Polar notifies it the moment a session is uploaded. Polling stays on
either way, so a broken webhook costs latency and never data. This needs a reverse proxy or tunnel
with a valid certificate; without one, leave it unset.

## Persistent data

| Path | Contents |
|---|---|
| `/data/tokens` | The Polar access token and, if used, the webhook signing key |
| `/data/state/ledger.json` | Which exercises were already delivered |

Dreeve deletes files from the watch folder once imported, so the ledger is the only record of what
has already been fetched. Deleting it makes the connector re-download everything Polar still has.
