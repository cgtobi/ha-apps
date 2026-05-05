# Home Assistant add-on repository

This repository contains Home Assistant add-ons.

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fcgtobi%2Fha-apps)

## Add-ons

This repository contains the following add-on.

### [Statistics for Strava](./addon/statistics_for_strava)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armv7 Architecture][armv7-shield]

_Statistics for Strava dashboard with built-in daemon scheduling._

Note: This repository does not publish pre-built multi-arch images.  
The architecture badges reflect the add-on `arch` targets declared in the manifest and Dockerfile-based local builds using Docker BuildKit.

The Statistics for Strava add-on uses the official upstream GHCR image as its base image. To test the local build directly:

```sh
docker build -t statistics-for-strava-local ./statistics_for_strava
docker build --build-arg BUILD_FROM=ghcr.io/robiningelbrecht/statistics-for-strava:vX.Y.Z -t statistics-for-strava-local ./statistics_for_strava
```

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
