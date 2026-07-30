# Home Assistant add-on repository

This repository contains Home Assistant add-ons.

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fcgtobi%2Fha-apps)

## Add-ons

This repository contains the following add-ons.

### [Dreeve](./statistics_for_strava)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armv7 Architecture][armv7-shield]

_Dreeve dashboard with built-in daemon scheduling._

Note: This repository does not publish pre-built multi-arch images.  
The architecture badges reflect the add-on `arch` targets declared in the manifest and Dockerfile-based local builds using Docker BuildKit.

The Dreeve add-on uses the official upstream GHCR image as its base image. To test the local build directly:

```sh
docker build -t dreeve-local ./statistics_for_strava
docker build --build-arg BUILD_FROM=ghcr.io/dreeveapp/dreeve:v5.0.0 -t dreeve-local ./statistics_for_strava
```

### [Dreeve Garmin Connector](./dreeve_garmin_connector)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

_Imports Garmin Connect activities into Dreeve. Requires the Dreeve add-on with `import_mode: files` and `expose_share: true`._

The Dreeve Garmin Connector add-on uses the official upstream GHCR image as its base image. To test the local build directly:

```sh
docker build -t dreeve-garmin-connector-local ./dreeve_garmin_connector
docker build --build-arg BUILD_FROM=ghcr.io/dreeveapp/dreeve-garmin-connector:v1.0.0 -t dreeve-garmin-connector-local ./dreeve_garmin_connector
```

### [Dreeve Polar Connector](./dreeve_polar_connector)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

_Imports Polar Flow training sessions into Dreeve. Requires the Dreeve add-on with `import_mode: files` and `expose_share: true`, plus your own Polar API client and a one-time authorization in the browser._

The Dreeve Polar Connector add-on uses the upstream GHCR image as its base image. To test the local build directly:

```sh
docker build -t dreeve-polar-connector-local ./dreeve_polar_connector
docker build --build-arg BUILD_FROM=ghcr.io/dreeveapp/dreeve-polar-connector:0.1.3 -t dreeve-polar-connector-local ./dreeve_polar_connector
```

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
