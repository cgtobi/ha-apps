# Dreeve Wahoo Connector

## Setup

1. Install and start the Dreeve add-on with `import_mode: files` and `expose_share: true`. This puts
   its watch folder where this add-on can write to it.
2. Create an application at
   [developers.wahooligan.com](https://developers.wahooligan.com/applications). Register
   `http://<home-assistant-host>:8085/callback` as its redirect URI - the same host you reach Home
   Assistant on, with port 8085 - and leave the webhook URI blank.
3. Put the application's ID and secret in `wahoo_client_id` and `wahoo_client_secret`, and set
   `redirect_uri` to that exact same URL. Wahoo compares it against the registered one byte for byte.
4. Start the add-on and open `http://<home-assistant-host>:8085/` - the add-on page's **OPEN WEB UI**
   button, or the URL by hand - then use **Connect Wahoo Account** and approve access at Wahoo. An
   initial sync runs as soon as authorization succeeds.

Until step 4 the add-on log reports `authenticated=False` and nothing is delivered. That is expected,
not a failure. With `redirect_uri` still empty the log also prints a `NOTE:` naming the option, because
no authorization can complete before it matches the URL registered with your application.

The add-on is `amd64` only: upstream publishes a linux/amd64 image and nothing else, so the add-on is
not offered on ARM hosts.

## Options

| Option | Default | Meaning |
|---|---|---|
| `wahoo_client_id` | - | **Required.** From your application at developers.wahooligan.com. |
| `wahoo_client_secret` | - | **Required** to authorize, and to refresh the token afterwards. |
| `redirect_uri` | - | Sent to Wahoo exactly as typed, and must match the redirect URI registered with your application. Usually `http://<home-assistant-host>:8085/callback`. |
| `sync_time_window` | `1_week` | How far back a sync cycle reaches: `1_day`, `1_week`, `1_month`, `1_year` or `all_time`. |
| `sync_cron` | `0 * * * *` | 5-field cron expression for scheduled syncs, **in UTC**. Hourly by default. Empty means the connector's own default of 02:00 UTC daily. |
| `tz` | `Etc/GMT` | Timezone for the log timestamps. It does **not** move `sync_cron`, which upstream evaluates in UTC. |
| `watch_dir` | - | Leave empty to auto-detect the Dreeve add-on's watch folder. Set it if auto-detection reports several candidates. |
| `log_level` | `info` | `debug`, `info`, `warning`, `error` or `critical`. |
| `extra_env` | `[]` | Extra connector settings as `KEY=VALUE`, for example `WAHOO_SCOPES=user_read workouts_read` or `USE_HTTPS=true`. |

Clearing `sync_time_window` or `sync_cron` does not export an empty value; the add-on omits the
variable, so upstream's own default applies (`1_week`, and daily at 02:00 UTC). To switch scheduled
syncs off altogether, add `SYNC_CRON=` to `extra_env` - that exports the variable empty, which is how
upstream is told to run no schedule. Syncing on demand from the dashboard still works.

`extra_env` cannot set `DATA_DIR`, `PORT`, `WATCH_DIR`, `STATE_DIR` or `VERIFY_FILES_ON_DISK`: the
add-on owns those, and overriding them would break persistence, the token store and the sync history,
the dashboard and the watchdog, or delivery into Dreeve. Attempts are logged and ignored.

`VERIFY_FILES_ON_DISK` is the one worth explaining, because the name reads like a safety net and it is
the opposite of one here. Upstream skips a workout that its sync history already records; switching
this on makes it also require the downloaded file to still be on disk. Under Dreeve it never is -
Dreeve deletes every file it imports - so every workout inside `sync_time_window` would be downloaded
again on every cycle, spending Wahoo's daily quota and re-importing the same rides, with nothing in the
log to say why.

Useful `extra_env` settings: `WAHOO_SCOPES` (default `user_read workouts_read`), `USE_HTTPS` (see
below) and `SYNC_CRON=` as described above.

## Troubleshooting

**No OPEN WEB UI button?** Home Assistant builds it from the host port published for 8085, taken from
the add-on's **Configuration → Network** panel. If that field is empty the button disappears. Fill it
in with `8085` and restart, or open `http://<home-assistant-host>:8085/` by hand - the button is only a
shortcut.

**Changed the host port?** Everything must agree: the port in **Network**, the `redirect_uri` option,
and the redirect URI registered with your Wahoo application. Wahoo rejects a redirect it does not know
verbatim, so remapping 8085 to, say, 8185 means registering
`http://<home-assistant-host>:8185/callback` at Wahoo as well and changing `redirect_uri` to match.

**Wahoo refuses a plain-HTTP redirect?** Register an `https://<home-assistant-host>:8085/callback` URI
instead and set `redirect_uri` to it. An `https://` redirect makes the connector serve the dashboard
over TLS with a certificate it generates itself into `/data/state`, so the browser shows a warning
that has to be accepted once. `USE_HTTPS=true` in `extra_env` has the same effect and is not needed on
top of an `https://` redirect.

The add-on logs a `NOTE:` in this case, because the **OPEN WEB UI** button still points at `http://`
and then answers nothing at all: open the `https://` URL by hand. Everything else keeps working - the
status loop tries `http://` first and falls back to `https://` with verification disabled, since that
certificate is self-signed by construction and the connection never leaves the container.

**Why a port and not ingress:** the redirect URI has to be registered with Wahoo in advance, and Home
Assistant's ingress URL carries a session token that changes whenever the add-on restarts, so it can
never be registered. The add-on therefore publishes the dashboard on host port 8085.

**`sync_cron` is UTC.** Upstream schedules on `datetime.utcnow()`, so the `tz` option shifts log
timestamps and nothing else. `0 4 * * *` fires at 04:00 UTC no matter what `tz` says.

**Manual sync:** the dashboard's **Sync Now**, or from a shell:

```sh
curl -X POST http://<home-assistant-host>:8085/api/sync
```

## Reading the log

One line is logged whenever something worth knowing about the connector's status changes - not on every
poll, which happens every five minutes:

```
authenticated=True next_sync_time=... last_sync_history=... last_result_status=success total_downloaded=42 is_syncing=False last_result_errors=[]
```

Compared between polls, so a change earns a line: `authenticated`, `next_sync_time`,
`last_sync_history` and `last_result_status`. Reported in the line but never compared:
`total_downloaded`, `is_syncing` and `last_result_errors` - they carry the detail you read once a line
has been earned.

- `authenticated=False` means nobody has authorized yet. The add-on still runs, and the watchdog still
  reports it healthy, because no restart can repair a missing authorization.
- `last_sync_history` is upstream's record of the last completed sync; `next_sync_time` is when the
  schedule fires next.
- `last_result_status` and `last_result_errors` come from the last cycle this process ran, so both read
  `None` until one has finished - a restart resets them.
- `total_downloaded` counts every workout upstream's sync history records, plus any `.fit` file in the
  watch folder that the history does not know about. It therefore keeps counting workouts Dreeve has
  already imported and deleted; the dashboard lists those with a size of `N/A (Processed)`.
- The connector logs its own line per downloaded workout (`Successfully downloaded new workout ...`).
  Nothing is logged after that, because nothing else happens to the file - it is written into the
  watch folder and Dreeve picks it up from there.

A quiet log therefore means nothing changed. The one exception: if the status cannot be read at all for
three polls in a row - about 15 minutes - the add-on logs a single warning, because "not up yet" and
"never coming up" otherwise look identical.

Both the status lines and the connector's own output follow the `log_level` option, so `warning` and
above silence them entirely, and `debug` adds a line per workout upstream decided to skip. The add-on's
startup messages are printed unconditionally, since an add-on that cannot start has to say so.

## Persistent data

| Path | Contents |
|---|---|
| `/data/state/tokens.json` | The Wahoo access and refresh tokens, refreshed automatically |
| `/data/state/sync_history.json` | Upstream's record of which workouts it downloaded |
| `/data/state/cert.pem`, `/data/state/key.pem` | The self-signed certificate, only when the dashboard serves HTTPS |

That is all of it. The `.fit` files themselves are not kept here: the add-on exports `STATE_DIR=/data/state`
and `WATCH_DIR=<Dreeve's watch folder>`, so downloads land in the watch folder and are Dreeve's to
delete. The add-on's data, and every Home Assistant backup that includes it, stays a few kilobytes
regardless of how many workouts have been synced.

Deleting `sync_history.json` makes upstream download every workout in `sync_time_window` from Wahoo
again and hand it to Dreeve a second time - harmless, since Dreeve skips a workout it has already
imported, but it spends Wahoo's daily request quota. Deleting `tokens.json` requires authorizing again
from the dashboard.
