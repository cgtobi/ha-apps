# Dreeve Garmin Connector

## Setup

1. Install and start the Dreeve add-on with `import_mode: files` and `expose_share: true`. This puts
   its watch folder where this add-on can write to it.
2. Set `garmin_email` and `garmin_password` here, then start this add-on.
3. Watch the log. Without multi-factor authentication you are done: the log reports the session was
   stored, and the first sync starts immediately.
4. With multi-factor authentication, the log says Garmin emailed a code. Put it in the `mfa_code`
   option, restart the add-on, and the login completes.

After a successful login the session is stored in the add-on's own data directory and refreshes
itself. `garmin_password` is only needed to log in; you may blank it afterwards, at the cost of
having to set it again if the session ever dies.

## Options

| Option | Default | Meaning |
|---|---|---|
| `garmin_email` | - | **Required.** Your Garmin Connect account. |
| `garmin_password` | - | Needed until a session exists. |
| `mfa_code` | - | The code Garmin emailed, for accounts with multi-factor authentication. |
| `since` | `-30d` | How far back the **first** run reaches: a date (`2026-01-01`), an offset (`-30d`, `720h`) or `now`. Ignored afterwards. |
| `tz` | `Etc/GMT` | Timezone for log timestamps and date comparisons. |
| `watch_dir` | - | Leave empty to auto-detect the Dreeve add-on's watch folder. Set it if auto-detection reports several candidates. |
| `log_level` | `info` | `debug`, `info`, `warning`, `error` or `critical`. |
| `extra_env` | `[]` | Extra connector settings as `KEY=VALUE`, for example `POLL_INTERVAL=7200`. See the [connector docs](https://docs.dreeve.app/#/integrations/garmin-connect). |

`extra_env` cannot set `GARMINTOKENS`, `STATE_DIR`, `WATCH_DIR` or `HTTP_ADDR`: the add-on owns those,
and overriding them would break persistence or the watchdog. Attempts are logged and ignored.

## Why the first sync is slow

A cycle downloads at most 25 activities and then waits for the next hour, deliberately - asking
Garmin for hundreds of files at once is the fastest way to get an account rate-limited. A large
history therefore backfills over days. The add-on log reports the remaining `backlog` whenever it
changes.

## Reading the log

One line is logged whenever something worth knowing about the connector's status changes — not on
every cycle. `lastSuccessfulSync` and `nextRunAt` are reported but deliberately not compared, since
they advance on every cycle by construction and would turn this into a heartbeat. These lines follow
the `log_level` option, so `warning` and above silence them entirely.

```
healthy=True authentication=ok backlog=42 backoffSeconds=0 lastSuccessfulSync=... nextRunAt=...
```

- `authentication` anything other than `ok` means the session is dead: set `garmin_password` again,
  restart, and re-enter a code if asked. Its value is the connector's full error text, so this line
  gets long when something is wrong.
- While there is no session, the connector logs its own advice to run
  `docker compose run --rm garmin-connector login`. **Ignore that.** It is written for Docker Compose
  users; there is no such command on Home Assistant, which is why this add-on logs in for you.
- `backoffSeconds` above zero means Garmin rate-limited the connector and it is waiting.
- `backlog` is the number of activities still owed a download.

## Multi-factor codes

A login attempt is only made when no session exists, and at most once every 15 minutes - repeated
logins are what get a Garmin account rate-limited. If a code expires before you enter it, restart the
add-on to request a new one, keeping that 15-minute window in mind.

A leftover `mfa_code` does no harm: it is only read while a login is actually waiting for one.

## Persistent data

| Path | Contents |
|---|---|
| `/data/tokens` | The Garmin session |
| `/data/state/ledger.json` | Which activities were already delivered |

Dreeve deletes files from the watch folder once imported, so the ledger is the only record of what has
already been fetched. Deleting it makes the connector re-download everything from `since`.
