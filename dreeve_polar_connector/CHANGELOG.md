# Changelog

## 0.1.12

- feat: use the Polar connector's own logo for the add-on icon

## 0.1.11

- fix: respect log level configuration
- fix: don't advise setting `public_url` when `redirect_uri` is set

## 0.1.10

- feat: bump Polar connector to 0.1.3 [Changelog](https://github.com/dreeveapp/dreeve-polar-connector/releases)

## 0.1.9

- feat: bump Polar connector to 0.1.2 [Changelog](https://github.com/cgtobi/dreeve-polar-connector/releases)

## 0.1.8

- feat: bump Polar connector to 0.1.1 [Changelog](https://github.com/cgtobi/dreeve-polar-connector/releases)

## 0.1.7

- feat: add a `redirect_uri` option

## 0.1.6

- docs: explain Polar's catch-all page

## 0.1.5

- fix: ship a liveness healthcheck for connectors

## 0.1.4

- docs: warn that the authorization flow starts at `/authorize` and never at `/callback` — opening the latter by hand reports _"The state parameter is missing, unknown or expired"_, which is correct behaviour, not a fault. Also spell out that remapping the host port means updating the `public_url` option **and** the redirect URL registered with Polar, which rejects any redirect URI it does not know verbatim.

## 0.1.3

- docs: lead the setup with the authorization URL (`http://<host>:8080/authorize`) instead of the **OPEN WEB UI** button, and say what to do when that button is missing — Home Assistant builds it from the host port published for 8080 in the add-on's Network panel, so an empty mapping hides it.

## 0.1.2

- fix: pin the base image to the tag the upstream connector actually publishes

## 0.1.1

- fix: use correct docker image tag

## 0.1.0

- feat: bump Polar connector to 0.1.0 [Changelog](https://github.com/cgtobi/dreeve-polar-connector/releases)
