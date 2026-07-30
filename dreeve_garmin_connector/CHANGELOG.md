# Changelog

## 0.1.1

- fix: every start no longer takes Home Assistant 120 seconds to acknowledge (`Timeout while waiting for app ... to start`). `HEALTHCHECK NONE` does not remove a healthcheck — it writes `Test:["NONE"]` into the image config, so Supervisor still sees one and holds the app in state `startup` waiting for a health verdict Docker never emits for a disabled check, until `STARTUP_TIMEOUT` expires. The add-on now ships a liveness healthcheck instead: a TCP connect to the status port, healthy exactly while the sync process is alive and indifferent to the state of the Garmin session — the same signal as the watchdog.

## 0.1.0

- feat: bump Garmin connector to v1.0.0 [Changelog](https://github.com/dreeveapp/dreeve-garmin-connector/releases)
