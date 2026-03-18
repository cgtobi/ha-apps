# Statistics for Strava

## Required add-on options

- `strava_client_id`
- `strava_client_secret`
- `strava_refresh_token`
- `tz`
- `strava_challenge_history_html` (optional): paste HTML source from your Strava trophy-case page to import historical challenges/trophies
- `app_config_yaml.general.appUrl` must be set to a real reachable URL (placeholder values are rejected at startup)
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
- Startup fails fast if any required Strava option is empty.
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

- Access the web UI through the configured host port mapping on `8080` (`8080/tcp` is configurable in app network settings).
- `app_config_yaml` is authoritative: when non-empty, `/data/config/app/config.yaml` is reconciled from add-on options on startup and service restarts.
- On each config reconcile invocation, the add-on runs Doctrine migrations and then `app:strava:build-files` so extracted UI overrides are applied.
- When `reconcile_run_import=true`, reconcile runs `app:strava:import-data` once per container startup before build-files.
- When `strava_challenge_history_html` is non-empty, reconcile writes it to `/data/storage/files/strava-challenge-history.html`.
- The add-on creates `/var/www/storage -> /data/storage` so upstream challenge import code can read `storage/files/strava-challenge-history.html`.
- Strava trophy-case HTML import currently requires Strava UI language to be English.
- When `cron_import_expression` is non-empty, reconcile overwrites `daemon.cron` entry `importDataAndBuildApp` with `cron_import_expression` and `cron_import_enabled`.
- Manual edits to `/data/config/app/config.yaml` will be overwritten on restart when `app_config_yaml` is set.
- Init logs report which config source was used: `existing`, `options`, or `legacy`.
- Application file logs default to `info` level to keep persistent logs readable.
- Runtime secrets are injected via container environment only; no `.env.local` secrets file is written.
- Strava webhooks still require public HTTPS reachability to your webhook endpoint.

## Config template

```yaml
general:
  appUrl: "http://CHANGE_ME:8080/"
  appSubTitle: null
  profilePictureUrl: null
  athlete:
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
