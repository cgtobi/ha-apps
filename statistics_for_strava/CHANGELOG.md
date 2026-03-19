# Changelog

## 0.4.37

- fix: handle upstream mutex contention (`Lock "importDataOrBuildApp" is already acquired`) gracefully during reconcile by treating it as a skipped/deferred run for `app:strava:import-data` and `app:strava:build-files` instead of a hard failure

## 0.4.36

- fix: run ingress path rewrites even when `app:strava:build-files` fails, so existing generated HTML/JS still get ingress-safe relative asset/API paths

## 0.4.35

- chore: add UTC ISO-8601 timestamps to reconcile log lines (`[reconcile]`, `WARN`, `FATAL`) for easier startup-sequence diagnostics

## 0.4.34

- fix: remove aggressive reconcile API token rewrites from generated files and rely on runtime ingress shim + generic href/src/action normalization; keeps upstream `relativeUrl('api/...')` output intact

## 0.4.33

- fix: make ingress runtime shim normalize generic root-absolute in-app requests (`/...`) to relative (`./...`) while preserving `/api/hassio_ingress/...`, fixing remaining route 404s like `/month/...`

## 0.4.32

- fix: normalize root-absolute heatmap routes (`/heatmap/...` and same-origin absolute forms) in ingress runtime shim to keep heatmap requests under ingress prefix

## 0.4.1

- chore: improve reconcile logging when `app:strava:build-files` fails (include exit code, first/last 40 log lines, and persist full log to `/data/runtime/sfs-build-files.last.log`)

## 0.4.0

- feat: enable Home Assistant Ingress (`ingress: true`, `ingress_port: 8080`, `ingress_stream: true`) for proxied UI and SSE support
- change: allow startup with placeholder `general.appUrl` for ingress-only setups; keep warning for direct/public URL use cases
- docs: document ingress-first access model and webhook/public URL constraint

## 0.3.52

- docs: provide default config template

## 0.3.51

- fix: export Strava credentials in reconcile

## 0.3.50

- feat: add configurable `reconcile_run_import` add-on option (default `true`) to control startup import during reconcile
- feat: run import command before `app:strava:build-files` during reconcile with command auto-detection and diagnostics

## 0.3.49

- fix: enable cron and provide a sane default

## 0.3.48

- feat: bump Statistics for Strava to v4.7.3 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.3.47

- feat: bump Statistics for Strava to v4.7.2 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.3.46

- feat: add `strava_challenge_history_html` option to import manual challenge/trophy history
- feat: write challenge history HTML to `/data/storage/files/strava-challenge-history.html` during reconcile
- fix: create `/var/www/storage -> /data/storage` symlink for upstream challenge import path compatibility
- feat: add preflight visibility for challenge-history import readiness

## 0.3.45

- fix: run Doctrine migrations before `app:strava:build-files` during reconcile to avoid missing `KeyValue` table on fresh installs

## 0.3.44

- feat: add startup preflight logging for common 404 causes (config/build/runtime readiness)

## 0.3.43

- feat: add German translations in `translations/de.yaml`

## 0.3.42

- feat: add English translations for add-on configuration options and network label

## 0.3.41

- feat: log start/success messages when running `app:strava:build-files` during reconcile

## 0.3.40

- feat: expose `general.appUrl` via new add-on option `general_app_url`

## 0.3.39

- fix: run `app:strava:build-files` on every config reconcile invocation (not only on config hash changes)

## 0.3.38

- feat: add UI overrides for selected `general`, `appearance`, and `import` configuration keys
- feat: run `app:strava:build-files` automatically after reconciled config changes

## 0.3.36

- feat: add UI options to override `importDataAndBuildApp` cron schedule and enabled state
- feat: render reconciled config from options before validation/write

## 0.3.35

- fix: keep daemon alive with auto-restart loop and restore startup compatibility
- fix: export Strava env vars from `/data/options.json` for cron/import subprocesses

## 0.3.34

- feat: provide daemon sample config

## 0.3.33

- fix: ensure config propagation

## 0.3.32

- fix: harden startup validation and health grace semantics
- fix: replace synthetic heartbeat with daemon PID readiness check

## 0.3.31

- feat: pin base image to statistics-for-strava v4.7.1

## 0.3.30

- fix: Caddy static routing for manifest and assets

## 0.3.29

- feat: add runtime preflight loader and watchdog health endpoint

## 0.3.28

- feat: harden startup option validation and make forced config regen one-shot

## 0.3.27

- docs: added same privacy note

## 0.3.26

- feat: remove legacy startup scripts and align docs with current direct-port config behavior

## 0.3.25

- fix: clean up
- fix: clean up unused config
- fix: remove unused config

## 0.3.24

- feat: make web ui port configurable

## 0.3.23

- fix: harden startup config handling and centralize bootstrap in cont-init

## 0.3.22

- feat: make config yaml editable

## 0.3.21

- feat: persist db and served files

## 0.3.20

- feat: initial setup
