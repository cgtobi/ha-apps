# Adding a connector add-on

Dreeve imports whatever appears in its watch folder. A connector is a separate container that puts
files there, so each provider becomes its own thin add-on in this repository rather than another
option in the Dreeve add-on. `dreeve_garmin_connector/` and `dreeve_polar_connector/` are the working
examples; this describes what carries over. The two differ in exactly one place — how the user
authenticates — and that difference is the first thing to establish about a new provider.

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
| `Dockerfile` | `ARG BUILD_FROM=<upstream image>:<tag>` carrying its own default — Supervisor stopped providing `BUILD_FROM` automatically in 2026.04.0 — then `FROM ${BUILD_FROM}`; `HEALTHCHECK NONE`; `ENTRYPOINT ["/usr/local/bin/ha-start.sh"]` with `CMD []` |
| `config.yaml` | `map: [all_addon_configs:rw]`, `stage: experimental` while the provider API is unofficial, `watchdog: "tcp://[HOST]:[PORT:8080]"` |
| `.upstream-version` | The pinned **image** tag, e.g. `v1.0.0` or `0.1.0` — whatever the upstream registry actually serves, which is not always the git tag |
| `.upstream-repo` | `image_repo`, `git_url`, `display_name`, `changelog_url`, `tag_prefix` — read by `scripts/bump-upstream.sh` |
| `config.yaml` + `CHANGELOG.md` | Must agree; `.githooks/pre-commit` enforces it per add-on |
| `rootfs/usr/local/bin/ha-start.sh` | Prepare env → (create session, credential providers only) → status loop → `exec` the upstream entrypoint |
| `translations/en.yaml`, `de.yaml` | Option labels, one entry per option |
| `tests/run-tests.sh` | Host-mode unit tests by default, `--in-image` to run the same suites on the image's Python |

## Two authentication shapes

Decide which one the provider uses before writing anything else; roughly half the add-on follows from
it.

**Credentials the user can type (Garmin).** Email, password, and possibly a multi-factor code are all
add-on options, so the add-on logs in itself, once, at boot: `dreeve_ha/login.py`, a throttle, a
persisted MFA ticket, and a `__main__.py` step in `ha-start.sh` between `prepare` and the status loop.
The upstream daemon is never allowed to log in on its own.

**An OAuth redirect (Polar).** No typed value substitutes for the browser round trip, so the add-on
has *no login step at all* — `login.py`, the throttle, the ticket and `__main__.py` do not exist. What
replaces them is reachability: the upstream connector already serves `/authorize` and `/callback` on
its HTTP port, so `config.yaml` publishes that port and points `webui` at it:

```yaml
ports:
  8080/tcp: 8080
webui: "http://[HOST]:[PORT:8080]/authorize"
```

Ingress cannot be used for this. The provider only redirects to a URL registered for the client
beforehand, and Home Assistant's ingress path carries a session token that changes when the add-on
restarts. A published port gives a stable `http://<host>:8080/callback` to register.

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
warning and dropped — never a fatal error. On an OAuth connector `HTTP_ADDR` is doubly owned: turning
it off would remove the authorization page as well as the watchdog's only signal.

**Liveness-only watchdog.** Point the watchdog at the status port over TCP
(`tcp://[HOST]:[PORT:8080]`), not at the connector's `/healthz`. Provider connectors typically report
unhealthy on broken credentials or on a missing authorization, neither of which a restart can fix; a
TCP check only asks whether the sync process is alive. This mirrors the Dreeve add-on's own
`healthz.php`, which deliberately ignores import and credential failures.

**Disabled Docker HEALTHCHECK.** The upstream image's own `HEALTHCHECK` shells out to a command that
reads env vars for its verdict, but a `HEALTHCHECK` process only sees the image's static env — not
what `ha-start.sh` exports at runtime after sourcing its env file — so it would report unhealthy
forever regardless of actual state. On an OAuth connector there is a second reason: upstream reports
unhealthy *by design* until someone authorizes. Both add-ons set `HEALTHCHECK NONE` and rely solely on
the watchdog above; Home Assistant does not consult Docker's health status anyway.

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

## What is provider-specific

- Credential and client option names, and the provider's environment prefix — `garmin_email`/`GARMIN_*`
  versus `polar_client_id`/`POLAR_*`.
- The authentication shape and everything that hangs off it: see "Two authentication shapes" above.
  Do not assume the next provider has MFA at all, or an OAuth flow, before checking.
- Whether authorization needs a published port, and therefore whether `ports`, `ports_description` and
  `webui` belong in `config.yaml`.
- `SINCE` semantics and the per-cycle download cap. Both add-ons take a date, an offset like `-30d` or
  `now` and ignore it after the first run, but what "everything" means differs: Garmin can backfill
  years, while Polar's API only serves the last 30 days and nothing uploaded before authorization.
