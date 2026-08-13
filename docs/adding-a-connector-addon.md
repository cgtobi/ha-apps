# Adding a connector add-on

Dreeve imports whatever appears in its watch folder. A connector is a separate container that puts
files there, so each provider becomes its own thin add-on in this repository rather than another
option in the Dreeve add-on. `dreeve_garmin_connector/`, `dreeve_polar_connector/` and
`dreeve_wahoo_connector/` are the working examples; this describes what carries over.

How much carries over depends on the upstream. Garmin and Polar wrap one upstream template — the same
`dreeve-<provider>-connector` CLI, the same `WATCH_DIR`/`STATE_DIR` conventions, the same Debian base
with its own `docker-entrypoint.sh` — so between those two the add-on differs in little more than how
the user authenticates. Wahoo wraps an independent application that shares none of it, and copying the
polar add-on onto it would have produced something that boots and quietly re-downloads forever. So ask
four things about a new provider before writing anything:

- **How does the user authenticate** — typed credentials, or a browser round trip?
- **Can upstream be told where to write** its files, or is the download directory hardcoded?
- **Does its deduplication survive the consumer deleting delivered files**, or does it ask whether the
  file is still on disk?
- **Does upstream publish releases at all**, or only `latest` and per-commit tags?

The answers decide, in order: whether there is a login step, whether the add-on needs a relay, and
whether the pin can ever be resolved automatically. Each has its own section below.

## Why separate add-ons

Bundling a connector into the Dreeve add-on was measured and rejected: the Dreeve image is Alpine
(musl) while connector images are Debian-based, so a connector must be reinstalled from wheels rather
than copied in. That worked for Garmin (+93 MB, all `musllinux` wheels available) but the cost repeats
per provider and wheel availability is not guaranteed — upstream's own Dockerfile avoids Alpine for
exactly this reason. Separate add-ons use each upstream image as-is, and users install only the
providers they use.

## What every connector add-on needs

| File | Notes |
|---|---|
| `Dockerfile` | `ARG BUILD_FROM=<upstream image>:<tag>` carrying its own default — Supervisor stopped providing `BUILD_FROM` automatically in 2026.04.0 — then `FROM ${BUILD_FROM}`; a liveness `HEALTHCHECK` replacing upstream's (never `HEALTHCHECK NONE` — see below); `ENTRYPOINT ["/usr/local/bin/ha-start.sh"]` with `CMD []` |
| `config.yaml` | `map: [all_addon_configs:rw]`, `stage: experimental` while the provider API is unofficial, `watchdog: "tcp://[HOST]:[PORT:8080]"` |
| `.upstream-version` | The pinned **image** tag, e.g. `v1.0.0`, `0.1.0` or `sha-eb2e511` — whatever the upstream registry actually serves, which is not always the git tag |
| `.upstream-repo` | `image_repo`, `git_url`, `display_name`, `changelog_url`, `tag_prefix` — read by `scripts/bump-upstream.sh` |
| `config.yaml` + `CHANGELOG.md` | Must agree; `.githooks/pre-commit` enforces it per add-on |
| `rootfs/usr/local/bin/ha-start.sh` | Prepare env → (create session, credential providers only) → status loop → `exec` upstream: its entrypoint where it has one, otherwise the app itself (see "A thin base image owns nothing for you") |
| `translations/en.yaml`, `de.yaml` | Option labels, one entry per option |
| `tests/run-tests.sh` | Host-mode unit tests by default, `--in-image` to run the same suites on the image's Python |

## Two authentication shapes

Decide which one the provider uses before writing anything else; roughly half the add-on follows from
it.

**Credentials the user can type (Garmin).** Email, password, and possibly a multi-factor code are all
add-on options, so the add-on logs in itself, once, at boot: `dreeve_ha/login.py`, a throttle, a
persisted MFA ticket, and a `__main__.py` step in `ha-start.sh` between `prepare` and the status loop.
The upstream daemon is never allowed to log in on its own.

**An OAuth redirect (Polar, Wahoo).** No typed value substitutes for the browser round trip, so the
add-on has *no login step at all* — `login.py`, the throttle, the ticket and `__main__.py` do not
exist. What replaces them is reachability: the upstream connector already serves `/authorize` and
`/callback` on its HTTP port, so `config.yaml` publishes that port and points `webui` at it:

```yaml
ports:
  8080/tcp: 8080
webui: "http://[HOST]:[PORT:8080]/authorize"
```

Which page to point at is upstream's choice, not a convention. Polar serves a bare `/authorize` that
redirects straight into the provider; the wahoo connector serves a whole dashboard on `/`, with a
**Connect Wahoo Account** button and the sync history below it, and `/callback` is only where the
provider returns. So `webui` names whichever page *starts* the flow — `webui: "http://[HOST]:[PORT:8080]/"`
for wahoo — and the documentation says so, because a user sent to `/callback` gets an error from a
half-finished flow rather than a button.

Ingress cannot be used for this. The provider only redirects to a URL registered for the client
beforehand, and Home Assistant's ingress path carries a session token that changes when the add-on
restarts. A published port gives a stable `http://<host>:8080/callback` to register.

The host side of that port is worth choosing rather than copying, because two OAuth connectors can be
installed at once: the polar add-on already publishes host 8080, so the wahoo add-on maps
`8080/tcp: 8085` — which is also upstream's own documented number — and neither user has to remap
anything. The container side stays add-on-owned in both, since the watchdog and the `HEALTHCHECK` are
written against it.

The provider's "public URL" stays a plain option rather than something derived from the Supervisor API:
it has to match a registered redirect URL exactly, and the user is typing that URL into the provider's
admin page anyway. Guessing a hostname that then fails to match produces a worse error than asking.

## Patterns worth copying

**Watch-folder resolution.** The Dreeve add-on's slug prefix depends on how it was installed
(`local_…` versus a repository hash), so match by suffix — `dreeve_ha/watchdir.py` globs
`/addon_configs/*statistics_for_strava/watch` — and fail loudly when there are zero or several
candidates, with a `watch_dir` option as the override. Requires the Dreeve add-on to run with
`expose_share: true`.

**Add-on-owned variables.** Expose a free-form `extra_env` list (`KEY=VALUE` strings) rather than one
option per upstream knob, and refuse the variables the add-on manages. Garmin's `env.py` defines
`OWNED = ("GARMINTOKENS", "STATE_DIR", "WATCH_DIR", "HTTP_ADDR")` and Polar's the same with
`POLAR_TOKENS`; an `extra_env` entry naming one of these, or one that isn't `KEY=VALUE`, is logged as a
warning and dropped — never a fatal error. Wahoo's is `("DATA_DIR", "PORT", "WATCH_DIR",
"DREEVE_WATCH_DIR")` — one upstream variable owns persistence, the token store *and* the relay's source
directory there, and the last two entries are explained under "Relay when upstream's dedup checks the
disk". On an OAuth connector the port variable — `HTTP_ADDR` on the sibling upstreams, `PORT` on
wahoo's — is doubly owned: moving it would remove the authorization page as well as the watchdog's only
signal.

**Liveness-only watchdog.** Point the watchdog at the status port over TCP
(`tcp://[HOST]:[PORT:8080]`), not at the connector's `/healthz`. Provider connectors typically report
unhealthy on broken credentials or on a missing authorization, neither of which a restart can fix; a
TCP check only asks whether the sync process is alive. This mirrors the Dreeve add-on's own
`healthz.php`, which deliberately ignores import and credential failures.

**Replaced Docker HEALTHCHECK — never `HEALTHCHECK NONE`.** The upstream images' own checks shell out
to a command that reads env vars for its verdict, but a `HEALTHCHECK` process only sees the image's
static env — not what `ha-start.sh` exports at runtime after sourcing its env file — so it reports
unhealthy forever regardless of actual state. On an OAuth connector there is a second reason: upstream
reports unhealthy *by design* until someone authorizes.

Disabling it is a trap, and cost two releases here. `HEALTHCHECK NONE` writes `Test:["NONE"]` into the
image config rather than removing the key, and Supervisor branches on the key's presence:

```python
AppState.STARTUP if self.instance.healthcheck else AppState.STARTED
```

An app in `STARTUP` becomes `STARTED` only on a health event, which Docker never emits for a disabled
check — so every single start waits out the full 120s `STARTUP_TIMEOUT` and logs
`Timeout while waiting for app ... to start`, while the container itself runs perfectly.

Note the asymmetry in that branch: an image carrying *no* `HEALTHCHECK` key at all goes straight to
`STARTED`, so `dreeve-wahoo-connector` — which ships none — could have been left alone. It still gets a
liveness check, for the health signal in the UI and the same reasoning as the watchdog; what is never
acceptable is the middle option, `HEALTHCHECK NONE`, which is strictly worse than either.

Ship a liveness check instead, mirroring the TCP watchdog — healthy exactly while the sync process
listens, indifferent to credentials or authorization:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/opt/venv/bin/python", "-c", "import socket; socket.create_connection(('127.0.0.1', 8080), 3).close()"]
```

Hardcode the port: it is add-on-owned, and a `HEALTHCHECK` could not read `HTTP_ADDR` anyway. Verify
both directions before shipping — `docker inspect -f '{{.State.Health.Status}}'` must reach `healthy`
within seconds of boot, and a container started with `--entrypoint sleep` must reach `unhealthy`.

**Entrypoint takeover, not CMD reliance.** The Dockerfile sets `CMD []` and replaces
`ENTRYPOINT` with `ha-start.sh`. The script itself ends with `exec docker-entrypoint.sh run` — it
names the upstream entrypoint explicitly rather than trusting whatever `CMD` the base image shipped,
so a change to a since-removed default command upstream can't silently do the wrong thing.

**Add-on never logs in via the daemon** *(credential providers only)*. The environment the add-on
builds never sets the upstream "allow password login" flag (Garmin's is `ALLOW_PASSWORD_LOGIN`), so the
connector daemon itself never attempts a login. All authentication happens once, at boot, in the
add-on's own `login` step.

**Login throttle** *(credential providers only)*. Any add-on that logs in automatically at boot needs one: providers rate-limit
logins far more aggressively than reads. Garmin's `login.py` records the attempt timestamp in
`/data/login-attempt` and refuses to retry within `THROTTLE_SECONDS` (900s = 15 min), even when the
previous attempt failed. Check `has_session()` first — an existing, non-empty token store skips login
entirely, throttle included.

**MFA that survives a restart (if the provider has it).** Garmin's flow calls
`Garmin(return_on_mfa=True)`; a `needs_mfa` result yields a `client_state` ticket that is persisted
(`secretfile.write`, JSON with a pickle fallback for objects `json` can't serialize) and answered later
with `client.resume_login(client_state, mfa_code)`. Both the initial attempt and the resume consume the
attempt-throttle and, on failure, delete the stored ticket so the next boot starts a clean login rather
than replay a spent one. Do not assume another provider has MFA at all, or that its flow can survive a
process restart — verify before copying this.

**Secrets written at a safe mode from creation.** `secretfile.write()` uses `os.open(..., O_CREAT,
0o600)` rather than `Path.write_bytes()` followed by `chmod()` — the write-then-chmod sequence creates
the file under the process umask first, leaving a window where a password, client secret or session
ticket is world-readable. Used for the sourced env file in both add-ons, and for the persisted MFA
ticket in the Garmin one.

**Status to log.** Poll the connector's status endpoint (`dreeve-<provider>-connector status`, every
300s) and log one reduced line, only when it changed. Pick the fields that name the states a user must
act on: Garmin reports `authentication`, Polar reports `authorization` plus the `authorizeUrl` to open,
which upstream nulls once authorized so the line goes quiet by itself. `statusloop.py` catches read errors inside
the loop and keeps going rather than exiting, because a crashed watcher leaves the same quiet log as a
healthy, unchanged one — the loop dying is the one failure mode that must never look identical to
success.

**Unit tests without a framework.** Keep the logic in a small Python package under
`rootfs/usr/local/lib/…`, inject the provider client so tests never touch the network, and run
`unittest` from the standard library. `tests/run-tests.sh` runs the suite on the host with
`PYTHONPATH` set only for that invocation, and again inside the built image with `--in-image` (which
also passes `PYTHONPATH` as a one-off `docker run -e`, never baked into the image). Keeping
`PYTHONPATH` out of the image's own `ENV` matters at runtime too: the connector process is `exec`'d
from the same shell that sourced the add-on's env, so an image-wide `PYTHONPATH` would put the add-on's
package on the upstream connector's import path and risk a name collision shadowing its modules.

**Release tooling needs no code changes.** `scripts/bump-upstream.sh` and
`scripts/check-release-consistency.sh` discover add-ons by globbing `*/config.yaml`, and read
per-add-on facts from that add-on's own `.upstream-repo`. A new add-on only needs `.upstream-version`
and `.upstream-repo` in place — no script edits. Its `CHANGELOG.md` must carry the canonical line the
bump script itself generates for the pinned tag — `- feat: bump <display_name> to <tag>
[Changelog](<changelog_url>)`, anywhere in the file, since docs-only and fix-only releases sit on top
of it — or `bump-upstream.sh check` and `.githooks/pre-commit` will reject the commit.

**Check the published image tag, not the git tag.** These differ more often than they look like they
should. `dreeve-polar-connector`'s release workflow renders git tag `v0.1.0` as image tag `0.1.0`,
because `docker/metadata-action`'s `{{version}}` strips the leading `v`; the Garmin and Dreeve upstreams
publish `v`-prefixed tags. Each `.upstream-repo` therefore declares `tag_prefix` (`v`, or empty), which
`bump-upstream.sh` applies when it resolves a tag — a missing field means `v`, the historical
assumption. Getting this wrong is not subtle at install time (`not found` on `load metadata`), but it is
invisible to every local check, so read the registry before pinning:

```sh
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:<owner>/<image>:pull&service=ghcr.io" | \
  python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/<owner>/<image>/tags/list
```

Two more registry facts that cost a build each: Home Assistant's Supervisor pulls **anonymously**, so a
private GHCR package fails with 401 however the repository is configured — package visibility is set
per package and can be public while the source repository stays private. And Supervisor builds add-on
images with `pull: True`, so preloading the base image into the host's Docker does not help.

An upstream repository that is not public yet is a related constraint: `bump-upstream.sh <addon>`
resolves the newest tag with `git ls-remote`, which hangs or fails on a private or missing repository.
Pin `.upstream-version` and the `ARG BUILD_FROM` default by hand until it is published; `check` works
regardless, because it only compares local files.

**Relay when upstream's dedup checks the disk.** Before wiring a connector's output directory straight
at the watch folder, answer the consumer-deletes question. `dreeve-wahoo-connector` skips a workout only
when its `sync_history.json` *and* the downloaded file agree — `if workout_id in downloaded_map and
os.path.exists(dest_path)` — while Dreeve **deletes** every file it imports. Pointing it at the watch
folder therefore re-downloads the whole `SYNC_TIME_WINDOW` on every cron fire, forever, burning the
provider's quota (Wahoo: 250/day) and re-importing the same workouts, while every status field reads
healthy. So `/data/downloads` stays the connector's private, never-pruned directory and the add-on
copies out of it: `dreeve_ha/relay.py` polls it every 15s for `*.fit`, copies to `<name>.tmp` in the
watch folder, `os.replace`s it into place, and keeps its own ledger in `/data/state/relayed.json`. The
cost is disk: the add-on's data — and therefore every Home Assistant snapshot — grows by 200–500 KB per
workout, which the add-on's `DOCS.md` says out loud.

Patching a copy of upstream's `app/sync.py` into the image is *not* the shortcut it looks like:
overridden upstream files rot silently on the next bump — a patched copy either crashes at boot or
serves dead URLs the moment upstream moves the file it was copied from, which the Dreeve add-on in this
repository has already paid for.

Name the relay's own variable carefully. The add-on exports `DREEVE_WATCH_DIR`, read by `relay.py`, and
`env.py` refuses **both** `DREEVE_WATCH_DIR` and `WATCH_DIR` from `extra_env` even though it never
exports the latter. `WATCH_DIR` is the name a planned upstream change would make *upstream* honour, so
using it for the add-on's private channel would mean the first bump onto such a build has upstream
writing directly into the folder Dreeve empties — with the relay still running and the dedup still
asking whether the file exists, i.e. the full re-download loop, arrived at by doing nothing but bumping
a pin. Never give an add-on-private variable a name upstream might one day claim.

**Pinning without upstream releases.** When the upstream workflow publishes only `latest` and
`sha-<short>` — no git tags, no semver image tags — pin a `sha-` tag and record that the pin is manual.
`bump-upstream.sh bump <addon> sha-XXXXXXX` accepts it, because `normalize_version` only strips a
leading `v` and prepends `tag_prefix` (empty for this upstream). `bump-upstream.sh <addon>`, the
auto-resolve form, **cannot**: it reads `git ls-remote --tags` and matches `vX.Y.Z`/`X.Y.Z` only, so it
exits with an error rather than picking something wrong. `check` is unaffected — it only compares local
files — which is why `dreeve_wahoo_connector` needs no script change at all.

Finding the newest build is the real trap: `/tags/list` is **unordered**, so the last entry is not the
newest and neither is the largest-looking hash. Identify it by digest — the `sha-` tag whose
`Docker-Content-Digest` equals `latest`'s is the current build. The loop that does it lives in the
wahoo add-on's `.upstream-repo` comment and in that add-on's design spec; also set `changelog_url` to
the upstream's commit list rather than a releases page that will always be empty.

**Status over HTTP when there is no status CLI.** Same shape as the CLI version — 300s poll, one
reduced line, logged only when it changed, read errors caught inside the loop — but the source is the
connector's own endpoint (`GET http://127.0.0.1:8080/api/status`) instead of a subprocess. Two things
differ. Nested fields have to be flattened before comparison: `statusloop.py` lifts `last_result.status`
and `last_result.errors` to top-level keys, because comparing dicts across polls compares things that
were never meant to be compared. And counters that move within a cycle must stay out of the comparison
while staying in the line — `total_downloaded`, `is_syncing` and `last_result_errors` are reported but
not compared, or the loop emits a line per poll and becomes a heartbeat that buries the one line worth
reading. Since a status source can also simply never come up, three consecutive unreadable polls earn
one warning: "not started yet" and "never coming up" are otherwise the same silence.

**A thin base image owns nothing for you.** Both sibling upstreams are Debian images with `/opt/venv`
and a `docker-entrypoint.sh` that handles TZ and PUID before running the daemon. `python:3.11-slim`,
which the wahoo connector uses, has **none** of it: no `ENTRYPOINT`, no `/opt/venv`, no timezone or
PUID handling. So `ha-start.sh` runs the app itself (`cd /workspace && exec /usr/local/bin/python -m
app.main`) rather than handing over to an upstream entrypoint that does not exist; `TZ` is the add-on's
own to export from its options; and both the `HEALTHCHECK` and `tests/run-tests.sh --in-image` call
`/usr/local/bin/python`, not `/opt/venv/bin/python`. Read the base image's entrypoint and interpreter
path before copying either line from another add-on — a wrong interpreter path in a `HEALTHCHECK` fails
the same way a dead app does, and the container looks broken while it is fine.

**An amd64-only upstream constrains `arch`.** Check the platforms the base image actually publishes —
`docker buildx imagetools inspect ghcr.io/<owner>/<image>:<tag>` — before copying an `arch` block from a
sibling add-on. `dreeve-wahoo-connector` is `linux/amd64` only, so `dreeve_wahoo_connector/config.yaml`
lists `amd64` alone, with a comment saying to add `aarch64` back when upstream builds multi-arch. An
`arch` list wider than the base image offers the add-on on hosts where it cannot even be pulled: the
user sees it in the store, installs it, and the build fails on `load metadata` — a nothing-to-do-with-me
error, hours after the wrong line was copied.

## What is provider-specific

- Credential and client option names, and the provider's environment prefix — `garmin_email`/`GARMIN_*`
  versus `polar_client_id`/`POLAR_*` versus `wahoo_client_id`/`WAHOO_*`.
- The authentication shape and everything that hangs off it: see "Two authentication shapes" above.
  Do not assume the next provider has MFA at all, or an OAuth flow, before checking.
- Whether authorization needs a published port, and therefore whether `ports`, `ports_description` and
  `webui` belong in `config.yaml`.
- `SINCE` semantics and the per-cycle download cap. Garmin and Polar both take a date, an offset like
  `-30d` or `now` and ignore it after the first run, but what "everything" means differs: Garmin can
  backfill years, while Polar's API only serves the last 30 days and nothing uploaded before
  authorization.
- Whether the history window is even a date. Wahoo's is an **enum** — `SYNC_TIME_WINDOW` takes
  `1_day|1_week|1_month|1_year|all_time` — so that add-on keeps upstream's name and values as a
  dropdown rather than pressing them into this repository's `since`. A `since` option that accepted
  different kinds of value per add-on would be worse than a differently named one.
- Whether the schedule is an interval or a cron expression, **and in which timezone it is evaluated**.
  Garmin and Polar take `POLL_INTERVAL` seconds; wahoo takes `SYNC_CRON` (the add-on defaults it to
  hourly, `0 * * * *`, rather than upstream's daily 02:00). Upstream evaluates that expression with
  `datetime.utcnow()`, so the add-on's `tz` option does **not** shift it — `tz` only moves log
  timestamps — and the documentation has to say so, or a user setting `tz` will believe they moved the
  sync.
- Whether upstream honours `LOG_LEVEL` at all. Wahoo's `logging.basicConfig(level=logging.INFO)` is
  hardcoded and no environment variable overrides it, so that add-on ships **no** `log_level` option: an
  option that silently does nothing is worse than an absent one. It arrives when upstream's variable
  does.
