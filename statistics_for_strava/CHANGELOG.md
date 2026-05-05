# Changelog

## 0.4.71

- feat: migrate to Home Assistant BuildKit model

## 0.4.70

- feat: bump Statistics for Strava to v4.7.9 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.4.69

- feat: bump Statistics for Strava to v4.7.8 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.4.68

- fix: test fix for issue 1993 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.4.67

- feat: bump Statistics for Strava to v4.7.7 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.4.66

- feat: bump Statistics for Strava to v4.7.6 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.4.65

- feat: bump Statistics for Strava to v4.7.5 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.4.64

- feat: bump Statistics for Strava to v4.7.4 [Changelog](https://statistics-for-strava-docs.robiningelbrecht.be/#/changelog)

## 0.4.62

- fix: stop installing heatmap history/click navigation hooks; keep only render-heal/fallback logic so landing route behavior remains upstream-driven

## 0.4.61

- fix: add heatmap fallback renderer in ingress shim that mounts Leaflet directly from `data-leaflet-routes` when upstream heatmap init leaves `#heatmap` empty (routes data + Leaflet available but no mount)

## 0.4.60

- fix: add guarded timeout-based one-time auto-reload on heatmap routes when Leaflet/data are present but `#heatmap` remains unmounted, matching the observed manual-reload recovery path in both direct and ingress mode

## 0.4.59

- fix: add guarded one-time ingress reload fallback for `/heatmap` when mount retries are exhausted and the map container is still not rendered, addressing intermittent `renderContent` network failures under ingress

## 0.4.58

- fix: broaden ingress heatmap click fallback detection to match non-anchor nav elements by text and common route/nav attributes containing `heatmap`

## 0.4.57

- fix: add ingress-only heatmap click fallback for non-anchor nav items (label `Heatmap`) to force `./heatmap` navigation when UI clicks do not trigger any route change

## 0.4.56

- fix: add minimal ingress-only History API remap for heatmap navigation (`/heatmap` -> `./heatmap`) so router-driven menu clicks without anchor links stay under ingress base path

## 0.4.55

- fix: remove invasive ingress heatmap history/click interception (which could cause flicker/overlay behavior) and replace with safe DOM anchor rewrite for heatmap links (`/heatmap` -> `./heatmap`)

## 0.4.54

- fix: change ingress heatmap navigation remap from `./dashboard#/heatmap` to `./heatmap` to avoid dashboard-overlay flicker/regression while keeping ingress-prefixed navigation
- fix: clear direct heatmap reload guard when map mounts so one-time auto-reload recovery can trigger again on subsequent blank first-load cases

## 0.4.53

- fix: broaden ingress-context detection in runtime shim (HA `/app/...`, slug paths, and non-`:8080` contexts) so heatmap navigation rewriting is actually active under Home Assistant ingress
- fix: run heatmap mount-heal retries even when `#heatmap` is not yet present on first navigation, improving first-load recovery without manual refresh

## 0.4.52

- fix: revert 0.4.51 heatmap server-side routing/link rewrites (`/heatmap` Caddy redirect and generated `href` remap) because they caused ingress regressions

## 0.4.51

- fix: add exact Caddy redirect for `/heatmap` -> `./dashboard#/heatmap` so first-load heatmap uses the SPA route initialization path (without broad deep-link redirects)
- fix: rewrite generated `/heatmap` nav links during reconcile to `./dashboard#/heatmap` for ingress-safe and direct-safe heatmap navigation

## 0.4.50

- fix: add ingress-only heatmap navigation shim to map `/heatmap` links/history updates to `./dashboard#/heatmap`, preventing ingress fallback-to-landing on heatmap navigation
- fix: add guarded direct-mode fallback reload for `/heatmap` when map container stays unmounted after bounded retries, matching observed manual-reload recovery

## 0.4.49

- fix: revert heatmap entry redirect (`/heatmap` -> `./dashboard#/heatmap`) due direct-mode regression/overlay; keep only non-navigational heatmap mount retries

## 0.4.48

- fix: normalize direct `/heatmap` entry to `./dashboard#/heatmap` in the ingress runtime shim so heatmap route initialization is consistent on first load (direct + ingress)

## 0.4.47

- fix: replace heatmap fallback navigation/reload with bounded in-place route lifecycle retries in ingress shim, preventing ingress resets while improving first-load heatmap mount reliability

## 0.4.46

- fix: replace heatmap one-time hard-reload workaround with a route-lifecycle mount heal (hashchange/popstate nudge + mutation observer) so first-load heatmap initialization is retried without full page reload

## 0.4.45

- fix: add guarded one-time heatmap self-heal reload in ingress shim when heatmap container remains empty after navigation, to recover from intermittent first-load mount race

## 0.4.44

- fix: remove Caddy SPA deep-link redirect block to restore upstream path-based page mounting (notably `/heatmap`) and avoid forcing hash-route redirects that break heatmap initialization

## 0.4.43

- chore: add UTC timestamps to remaining startup/service logs (`start.sh`, `00-init`, `sfs-startup-preflight.sh`, `services.d/web/run`, `services.d/daemon/run`) for consistent log chronology

## 0.4.42

- fix: narrow Caddy SPA deep-link redirects to top-level routes only (`/heatmap`, `/month`, `/activity`, `/segment`) so modal/detail HTML fetches like `/activity/*.html`, `/segment/*.html`, and `/month/*.html` are no longer intercepted

## 0.4.41

- fix: remove history/anchor navigation interception from ingress shim (keep only request normalization) to avoid regressions on direct hash-routed pages such as `/dashboard#/heatmap`

## 0.4.40

- fix: add reconcile `rewrite-only` mode and a background ingress rewrite loop in `start.sh` so cron-triggered rebuilds keep ingress-safe paths applied after daemon updates files

## 0.4.39

- fix: add Caddy SPA deep-link redirects for `/heatmap`, `/month/...`, `/activity/...`, and `/segment/...` to `./dashboard#...` so direct path navigation works under ingress and mounts the expected view

## 0.4.38

- fix: extend ingress runtime shim to normalize client-side navigation URLs (`history.pushState`, `history.replaceState`, and root-absolute anchor hrefs) so page routes like `/heatmap` and `/month/...` stay under ingress prefix

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
