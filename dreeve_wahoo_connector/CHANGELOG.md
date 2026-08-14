# Changelog

## 0.1.1

- feat: bump Wahoo connector to sha-4ed0b56 [Changelog](https://github.com/dreeveapp/dreeve-wahoo-connector/commits/main)
- feat: workouts land in Dreeve's watch folder as soon as they are downloaded. Upstream now honours
  `WATCH_DIR`, so the add-on no longer keeps a second copy of every `.fit` file and copies it across
- feat: `log_level` option, from `debug` to `critical`, now that upstream honours `LOG_LEVEL`
- fix: the dashboard and the OAuth callback moved to port 8085 inside the container, following
  upstream's own default. The published host port is unchanged, so nothing has to be reconfigured
- note: tokens, sync history and the generated certificate now live in `/data/state`; `/data/downloads`
  and `/data/config` are no longer used
- note: do not set `VERIFY_FILES_ON_DISK` through `extra_env` - it is refused, because Dreeve deletes
  what it imports and the check would re-download every workout in the sync window on every run

## 0.1.0

- feat: bump Wahoo connector to sha-eb2e511 [Changelog](https://github.com/dreeveapp/dreeve-wahoo-connector/commits/main)
- feat: initial release - imports Wahoo workouts into Dreeve
- note: pinned to a `sha-` image tag, because this upstream publishes no releases yet
- note: downloaded `.fit` files are kept in the add-on's own `/data/downloads` and copied into Dreeve's
  watch folder, because upstream re-downloads anything missing from that folder and Dreeve deletes what
  it imports
