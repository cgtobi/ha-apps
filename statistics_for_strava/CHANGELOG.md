# Changelog

## 0.4.30

- fix: normalize root-absolute segment routes (`/segment/...` and same-origin absolute forms) in ingress runtime shim so segment detail pages resolve under ingress prefix

## 0.4.29

- fix: remove broad activity token rewrites from reconcile sed passes to prevent ingress regressions and malformed API paths
- fix: keep activity/API path normalization in runtime ingress shim (`/activity/...`, `activity/...`, `/api./...`, `api./...`) instead of mutating generated bundles aggressively

## 0.4.28

- fix: prevent escaped activity rewrite from corrupting API routes (`/api/activity/...` -> `/api./activity/...`) by adding explicit normalization guards
- fix: inject `./js/ingress-api-shim.js` into generated HTML during reconcile and extend shim handling for root-absolute `/activity/...`, `/api/...`, and malformed `/api./...` requests

## 0.4.27

- fix: extend ingress rewrite on generated build HTML/JS and runtime `app.min.js` to normalize root-absolute API/activity tokens including bare (`"/api"`, `"/activity"`) and escaped (`\/api\/`, `\/activity\/`) forms
- fix: keep activities-page detail requests and activity map polylines under ingress prefix instead of falling back to host-root `/api/...` and `/activity/...`

## 0.4.26

- fix: normalize root-absolute API route tokens in runtime `app.min.js` rewrite (`"/api/..."`, `'/api/...'`, `` `/api/...` ``, and escaped `\/api\/...`) to ingress-safe relative `./api/...`
- fix: normalize escaped activity route tokens (`\/activity\/...`) to `./activity/...` to keep activities page navigation under ingress

## 0.4.25

- fix: remove malformed ingress sed replacement expressions (`\\/activity\\/#...`) that caused `sed: unmatched '|'` during reconcile and could break ingress asset rewriting

## 0.4.24

- fix: change activity route normalization from `./dashboard#/activity/...` to `./activity/...` and include escaped `\/activity\/` forms in HTML/JS rewrites, so activity XHR/page requests stay under ingress prefix

## 0.4.23

- fix: normalize `/activity/...` route strings to `./dashboard#/activity/...` in generated HTML and `app.min.js` using safe sed delimiters, so activity navigation works behind ingress without reintroducing sed substitution errors

## 0.4.22

- fix: restore Caddy static resource roots for `/css/*`, `/js/*`, `/libraries/*`, `/assets/*` to `/var/www/public` (instead of `/data/build/html`) to resolve ingress MIME/404 failures for frontend assets

## 0.4.21

- fix: remove fragile `sed` activity-route rewrite expressions that caused `sed: bad option in substitution expression` during reconcile
- fix: keep ingress stabilization by applying only safe build/html URL rewrites and Caddy static path serving

## 0.4.20

- fix: serve frontend static paths (`/css/*`, `/js/*`, `/libraries/*`, `/assets/*`) from `/data/build/html` in Caddy to prevent ingress root-absolute resource requests from returning text/plain 404/MIME errors

## 0.4.19

- fix: rewrite root-absolute activity route strings (`/activity/...`) to ingress-safe hash routes (`./dashboard#/activity/...`) in generated HTML and `app.min.js`, without touching `/api/activity/...` endpoints

## 0.4.18

- fix: normalize all root-absolute `href/src/action` URLs in generated HTML to relative `./...` during reconcile (while keeping protocol-relative `//...` untouched), so libraries/css/js/assets load under ingress prefix

## 0.4.17

- fix: rollback ingress shim/script-based rewrites to restore stable ingress rendering
- fix: strip previously injected `ingress-api-shim.js` tags from generated build HTML during reconcile
- fix: restore rewrite rules to the prior stable profile (static/API/assets/manifest + html/bare route normalization only)

## 0.4.16

- fix: avoid ingress URL duplication by excluding `/api/hassio_ingress/...` URLs from API shim normalization
- fix: normalize root-absolute `/activity/...` links in generated pages to `./dashboard#/activity/...` so activities-page navigation stays under ingress

## 0.4.15

- fix: replace brittle inline/js-text rewrites with a dedicated ingress API shim script (`/js/ingress-api-shim.js`) injected into generated HTML pages to normalize root-absolute `/api/...` requests at runtime

## 0.4.14

- fix: remove ingress runtime shim injection and switch to direct `app.min.js` normalization for `/api/...` paths (quoted, backtick, escaped, and expression-adjacent forms), reducing parse/regression risk

## 0.4.13

- fix: harden ingress API runtime shim by injecting it into all generated HTML pages and rewriting both relative and same-origin absolute `/api/...` URLs (including `fetch(Request)` inputs)

## 0.4.12

- fix: inject ingress API shim into generated HTML (`index.html`, `dashboard.html`) to force root-absolute `/api/...` calls to relative `./api/...` at runtime for `fetch`, `XMLHttpRequest`, and `EventSource`

## 0.4.11

- fix: apply ingress path normalization directly to `/var/www/public/js/dist/app.min.js` after build, so JS-generated `/api/...` and `/activity/...` requests become relative under ingress

## 0.4.10

- fix: extend ingress build-file normalization for API calls in minified JS by handling explicit `/api/activity/` tokens and template-literal backtick paths (``/api/...``)

## 0.4.9

- fix: normalize quoted root-absolute `/api` base tokens to relative `./api` in generated build files so activity XHR calls resolve under ingress prefix

## 0.4.8

- fix: prevent malformed `/api./activity/...` URLs by normalizing rewritten activity paths back to `/api/activity/...` in generated build files

## 0.4.7

- fix: correct escaped `/activity/` normalization replacement to avoid invalid JSON escape sequences in generated `app.min.js` (fixes `JSON.parse: bad escaped character`)

## 0.4.6

- fix: normalize `/activity/` path string tokens in generated build HTML/JS to relative `./activity/` so activity-page navigation stays under ingress prefix

## 0.4.5

- fix: restore ingress build-file rewrite rules to last known-good profile (root-absolute static/API/html/bare-route links to relative paths) and remove recent aggressive/special-case patterns

## 0.4.4

- fix: roll back aggressive ingress link rewrites that could corrupt generated dashboard HTML/JS
- fix: keep only minimal safe rewrite set for root-absolute static/API paths and `manifest.json`

## 0.4.3

- fix: normalize generic `/activity/` string tokens (including escaped `\/activity\/`) in generated build HTML/JS to ingress-safe `./dashboard#/activity/` links

## 0.4.2

- fix: revert `/activity/*` Caddy redirect fallback that could break web startup
- fix: keep activity deep-link normalization in reconcile and escape `#` correctly in sed replacements (`./dashboard#/activity/...`)

## 0.4.1

- fix: normalize root-absolute activity links (`/activity/...`) to ingress-safe hash routes (`./dashboard#/activity/...`) in generated build files

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
