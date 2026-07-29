# Adding a connector add-on

Dreeve imports whatever appears in its watch folder. A connector is a separate container that puts
files there, so each provider becomes its own thin add-on in this repository rather than another
option in the Dreeve add-on. `dreeve_garmin_connector/` is the working example; this describes what
carries over.

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
| `.upstream-version` | The pinned tag, e.g. `v1.0.0` |
| `.upstream-repo` | `image_repo`, `git_url`, `display_name`, `changelog_url` — read by `scripts/bump-upstream.sh` |
| `config.yaml` + `CHANGELOG.md` | Must agree; `.githooks/pre-commit` enforces it per add-on |
| `rootfs/usr/local/bin/ha-start.sh` | Prepare env → create session → status loop → `exec` the upstream entrypoint |
| `translations/en.yaml`, `de.yaml` | Option labels, one entry per option |
| `tests/run-tests.sh` | Host-mode unit tests by default, `--in-image` to run the same suites on the image's Python |

## Patterns worth copying

**Watch-folder resolution.** The Dreeve add-on's slug prefix depends on how it was installed
(`local_…` versus a repository hash), so match by suffix — `dreeve_ha/watchdir.py` globs
`/addon_configs/*statistics_for_strava/watch` — and fail loudly when there are zero or several
candidates, with a `watch_dir` option as the override. Requires the Dreeve add-on to run with
`expose_share: true`.

**Add-on-owned variables.** Expose a free-form `extra_env` list (`KEY=VALUE` strings) rather than one
option per upstream knob, and refuse the variables the add-on manages. Garmin's `env.py` defines
`OWNED = ("GARMINTOKENS", "STATE_DIR", "WATCH_DIR", "HTTP_ADDR")`; an `extra_env` entry naming one of
these, or one that isn't `KEY=VALUE`, is logged as a warning and dropped — never a fatal error.

**Liveness-only watchdog.** Point the watchdog at the status port over TCP
(`tcp://[HOST]:[PORT:8080]`), not at the connector's `/healthz`. Provider connectors typically report
unhealthy on broken credentials, which a restart cannot fix; a TCP check only asks whether the sync
process is alive. This mirrors the Dreeve add-on's own `healthz.php`, which deliberately ignores
import and credential failures.

**Disabled Docker HEALTHCHECK.** The upstream image's own `HEALTHCHECK` shells out to a command that
reads env vars for its verdict, but a `HEALTHCHECK` process only sees the image's static env — not
what `ha-start.sh` exports at runtime after sourcing its env file — so it would report unhealthy
forever regardless of actual state. The Garmin add-on sets `HEALTHCHECK NONE` and relies solely on the
watchdog above; Home Assistant does not consult Docker's health status anyway.

**Entrypoint takeover, not CMD reliance.** The Dockerfile sets `CMD []` and replaces
`ENTRYPOINT` with `ha-start.sh`. The script itself ends with `exec docker-entrypoint.sh run` — it
names the upstream entrypoint explicitly rather than trusting whatever `CMD` the base image shipped,
so a change to a since-removed default command upstream can't silently do the wrong thing.

**Add-on never logs in via the daemon.** The environment the add-on builds never sets the upstream
"allow password login" flag (Garmin's is `ALLOW_PASSWORD_LOGIN`), so the connector daemon itself never
attempts a login. All authentication happens once, at boot, in the add-on's own `login` step.

**Login throttle.** Any add-on that logs in automatically at boot needs one: providers rate-limit
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
the file under the process umask first, leaving a window where a password or session ticket is
world-readable. Used for both the sourced env file and the persisted MFA ticket.

**Status to log.** Poll the connector's status endpoint (Garmin: `dreeve-garmin-connector status`,
every 300s) and log one reduced line, only when it changed. `statusloop.py` catches read errors inside
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
and `.upstream-repo` in place — no script edits. Its `CHANGELOG.md` first entry must already match the
canonical line the bump script itself generates:
`- feat: bump <display_name> to <tag> [Changelog](<changelog_url>)`, or `check-release-consistency.sh`
and `.githooks/pre-commit` will reject the commit.

## What is Garmin-specific

- Credential option names (`garmin_email`, `garmin_password`) and the `GARMIN_*` environment
  variables.
- The multi-factor flow described above — check whether the next provider has MFA at all before
  copying it.
- `SINCE` semantics (a date, an offset like `-30d`, or `now`, ignored after the first run), and the
  per-cycle download cap that makes a first backfill take days.
