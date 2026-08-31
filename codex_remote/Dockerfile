# pinned (not :latest) for reproducible builds; bump deliberately when needed
FROM ghcr.io/home-assistant/base:3.24-2026.08.0

ARG BUILD_VERSION
ARG BUILD_ARCH

RUN apk add --no-cache bash ca-certificates curl git jq ripgrep fd procps su-exec openssh gcompat
# adduser -D leaves the shadow password "!"-locked, which sshd's platform_locked_account()
# check rejects for ALL auth methods (including pubkey), not just password; delete the
# password hash instead so the account is unlocked while password login stays disabled
# via sshd_config (PasswordAuthentication no / KbdInteractiveAuthentication no).
RUN adduser -D -u 1000 -h /data/home -s /bin/bash codex && passwd -d codex

COPY run.sh /run.sh
RUN chmod 0755 /run.sh

LABEL io.hass.version="${BUILD_VERSION}" io.hass.type="app" io.hass.arch="${BUILD_ARCH}"
CMD ["/run.sh"]
