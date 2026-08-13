# Changelog

## 0.1.0

- feat: bump Wahoo connector to sha-eb2e511 [Changelog](https://github.com/dreeveapp/dreeve-wahoo-connector/commits/main)
- feat: initial release - imports Wahoo workouts into Dreeve
- note: pinned to a `sha-` image tag, because this upstream publishes no releases yet
- note: downloaded `.fit` files are kept in the add-on's own `/data/downloads` and copied into Dreeve's
  watch folder, because upstream re-downloads anything missing from that folder and Dreeve deletes what
  it imports
