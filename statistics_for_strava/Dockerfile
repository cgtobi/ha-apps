ARG BUILD_FROM=robiningelbrecht/strava-statistics:v4.7.5
FROM ${BUILD_FROM}

RUN apk add --no-cache jq

COPY rootfs /

CMD ["sh", "/usr/local/bin/start.sh"]
