# Statistics for Strava

## Import modes

> **Not yet available.** File import is groundwork only — the `import_mode` and
> `expose_share` options are intentionally hidden from the add-on UI and the
> feature is not ready for use. The section below documents the planned behavior
> for when it is enabled.

The add-on supports two import modes, selected via `import_mode`:

- `stravaApi` (default): imports activities from the Strava API. Requires `strava_client_id`, `strava_client_secret`, `strava_refresh_token`.
- `files`: imports activities from local `.fit` / `.tcx` / `.gpx` files. Requires no Strava credentials. The athlete is built from config, so `general.athlete.firstName`, `general.athlete.lastName` and `general.athlete.gender` must be set.

### Providing files over SMB/CIFS (`files` mode)

1. Set `import_mode: files` and `expose_share: true`.
2. The add-on symlinks its file-import watch dir to its mapped config dir, exposed on the host as `/addon_configs/local_statistics_for_strava/watch`.
3. Make that path reachable over SMB/CIFS: in the official Samba add-on, enable the `addon_configs` share. The watch dir then appears under `\\HOST\addon_configs\statistics_for_strava\watch`.
4. Drop `.fit` / `.tcx` / `.gpx` files into that folder.

Notes:

- The daemon scans the watch dir and imports every ~5 minutes; a startup import also runs once per container start.
- Imported files are **deleted** from the watch dir by upstream after a successful import — this is expected behavior.
- `expose_share` only controls whether the watch dir is created and symlinked; the underlying mount (`addon_config:rw`) is always granted but scoped to this add-on's own config dir, not all of `/share`.

## Required add-on options

- `import_mode` (`stravaApi` or `files`; default `stravaApi`)
- `expose_share` (`true`/`false`, default `false`; exposes the file-import watch dir over the mapped config dir)
- `strava_client_id` (required in `stravaApi` mode)
- `strava_client_secret` (required in `stravaApi` mode)
- `strava_refresh_token` (required in `stravaApi` mode)
- `tz`
- `strava_challenge_history_html` (optional): paste HTML source from your Strava trophy-case page to import historical challenges/trophies
- `app_config_yaml.general.appUrl` must be a non-empty string
- Optional UI overrides (leave empty/zero to keep YAML values):
  - `general_app_url` (absolute URL; when set, overrides `general.appUrl`)
  - `general_app_subtitle`
  - `general_profile_picture_url`
  - `appearance_locale` (`en_US`, `fr_FR`, `it_IT`, `nl_BE`, `de_DE`, `pt_BR`, `pt_PT`, `sv_SE`, `zh_CN`)
  - `appearance_unit_system` (`metric` or `imperial`; default `metric`)
  - `appearance_time_format` (`12` or `24`; default `24`)
  - `import_number_of_new_activities_to_process_per_import` (default `250`)
  - `import_opt_in_to_segment_detail_import` (applied only if `import_opt_in_to_segment_detail_import_configured=true`)
- Optional UI cron override for `importDataAndBuildApp`:
  - `cron_import_expression` (5-field cron string; leave empty to keep YAML value)
  - `cron_import_enabled` (`true`/`false`, used when `cron_import_expression` is set)
- Optional startup import behavior:
  - `reconcile_run_import` (`true`/`false`, default `true`; runs one import command during reconcile before build-files)
- In `stravaApi` mode, startup fails fast if any required Strava option is empty. In `files` mode, Strava options are not required.
- Startup validates `config.yaml` structure and required keys before services start (legacy optional sections are tolerated).

> Privacy note: add-on options are persisted by Home Assistant on disk in `/data/options.json`.
> Do not store unnecessary sensitive personal data in options.

## Required persistent config file

This add-on requires:

- `/data/config/app/config.yaml`

At startup, the add-on will fail fast if this file is missing.

## Runtime model

This add-on runs both required processes inside one container:

- Web UI: `frankenphp` on port `8080`
- Scheduler/daemon: `bin/console app:daemon:run`
- Health endpoint: `GET /healthz` on port `8080` (used by Home Assistant watchdog; returns `503` if required runtime paths/config are unavailable or daemon process is not alive; includes short startup grace based on container startup marker to avoid flapping)
- `/manifest.json` and `/assets/*` are served from Symfony `public/`; dashboard `.html` is served from `/data/build/html`.

## Persistent directories

- `/data/config/app`
- `/data/storage/database`
- `/data/storage/files`
- `/data/storage/gear-maintenance`
- `/data/build`

## Notes

- Home Assistant Ingress is enabled and is the recommended way to access the UI from HA.
- Direct port access via `8080/tcp` remains available for external/reverse-proxy access.
- If `general.appUrl` remains `http://CHANGE_ME:8080/`, startup continues (for ingress compatibility), but webhook/public URL features should use a real public URL.
- During config render, placeholder `general.appUrl` is normalized to `./` (unless `general_app_url` is set) so ingress-prefixed asset/API paths stay under the ingress base path.
- `app_config_yaml` is authoritative: when non-empty, `/data/config/app/config.yaml` is reconciled from add-on options on startup and service restarts.
- On each config reconcile invocation, the add-on runs Doctrine migrations and then `app:strava:build-files` so extracted UI overrides are applied.
- When `reconcile_run_import=true`, reconcile runs one import once per container startup before build-files: `app:strava:import-data` in `stravaApi` mode, `app:cron:run-file-import` in `files` mode.
- When `strava_challenge_history_html` is non-empty, reconcile writes it to `/data/storage/files/strava-challenge-history.html`.
- The add-on creates `/var/www/storage -> /data/storage` so upstream challenge import code can read `storage/files/strava-challenge-history.html`.
- Strava trophy-case HTML import currently requires Strava UI language to be English.
- When `cron_import_expression` is non-empty, reconcile overwrites `daemon.cron` entry `importDataAndBuildApp` with `cron_import_expression` and `cron_import_enabled`.
- Manual edits to `/data/config/app/config.yaml` will be overwritten on restart when `app_config_yaml` is set.
- Init logs report which config source was used: `existing`, `options`, or `legacy`.
- Application file logs default to `info` level to keep persistent logs readable.
- Runtime secrets are injected via container environment only; no `.env.local` secrets file is written.
- Strava webhooks still require public HTTPS reachability to your webhook endpoint (ingress URL is not a public webhook endpoint).

## Config template

```yaml
general:
  appUrl: "http://CHANGE_ME:8080/"
  appSubTitle: null
  profilePictureUrl: null
  athlete:
    firstName: null  # required in files import mode
    lastName: null   # required in files import mode
    gender: null     # required in files import mode
    birthday: "YYYY-MM-DD"
    maxHeartRateFormula: "fox"
    restingHeartRateFormula: "heuristicAgeBased"
    heartRateZones:
      mode: relative
      default:
        zone1: { from: 50, to: 60 }
        zone2: { from: 61, to: 70 }
        zone3: { from: 71, to: 80 }
        zone4: { from: 81, to: 90 }
        zone5: { from: 91, to: null }
    weightHistory:
      "YYYY-MM-DD": 100
    ftpHistory:
      cycling: []
      running: []
appearance:
  locale: "en_US"
  unitSystem: "metric"
  timeFormat: 24
  dateFormat:
    short: "d-m-y"
    normal: "d-m-Y"
import:
  numberOfNewActivitiesToProcessPerImport: 250
  sportTypesToImport: []
  activityVisibilitiesToImport: []
  skipActivitiesRecordedBefore: null
  activitiesToSkipDuringImport: []
  optInToSegmentDetailImport: false
zwift:
  level: null
  racingScore: null
daemon:
  cron:
    - action: "importDataAndBuildApp"
      expression: "0 14 * * *"
      enabled: false
```
