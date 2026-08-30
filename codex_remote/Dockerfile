FROM ghcr.io/home-assistant/base:latest

ARG BUILD_VERSION
ARG BUILD_ARCH

RUN apk add --no-cache bash ca-certificates curl git jq ripgrep fd procps su-exec openssh gcompat
RUN adduser -D -u 1000 -h /data/home -s /bin/bash codex

COPY run.sh /run.sh
RUN chmod 0755 /run.sh

LABEL io.hass.version="${BUILD_VERSION}" io.hass.type="app" io.hass.arch="${BUILD_ARCH}"
CMD ["/run.sh"]
