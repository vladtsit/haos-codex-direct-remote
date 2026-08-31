#!/usr/bin/with-contenv bashio
set -euo pipefail

USER_NAME="codex"
HOME_DIR="/data/home"
PROJECT_DIR="/data/project"

mkdir -p "${HOME_DIR}/.codex" "${PROJECT_DIR}"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}" "${PROJECT_DIR}"

# su-exec runs argv directly with no intermediate shell, so config values are never re-parsed
run_as_codex() {
  (
    cd "${PROJECT_DIR}" || exit 1
    exec env HOME="${HOME_DIR}" CODEX_HOME="${HOME_DIR}/.codex" USER="${USER_NAME}" \
      su-exec "${USER_NAME}" "$@"
  )
}

idle_forever() {
  while true; do sleep 3600; done
}

DEFAULT_CODEX_VERSION="0.151.0"
STANDALONE_CODEX="${HOME_DIR}/.codex/packages/standalone/current/codex"
SSH_HOST_KEY_DIR="${HOME_DIR}/.ssh_host_keys"
SSH_AUTHORIZED_KEYS_FILE="${HOME_DIR}/.ssh/authorized_keys"
APP_SERVER_CONTROL_DIR="${HOME_DIR}/.codex/app-server-control"

# remote-control requires this installer-managed copy at a fixed CODEX_HOME path; using it
# exclusively (no npm install) keeps one binary, one version pin, no PATH ambiguity, and no
# risk of npm's own background auto-update silently drifting past CODEX_PINNED_VERSION.
# Reinstalls automatically if the installed binary doesn't match the pin (e.g. after the
# pin was bumped), since /data persists across restarts/rebuilds and a stale binary would
# otherwise never get replaced.
ensure_standalone_codex() {
  if [[ -x "${STANDALONE_CODEX}" ]]; then
    local installed_version
    installed_version="$("${STANDALONE_CODEX}" --version 2>/dev/null | awk '{print $NF}')"
    if [[ "${installed_version}" == "${CODEX_PINNED_VERSION}" ]]; then
      return 0
    fi
    bashio::log.info "Installed Codex ${installed_version:-unknown} != pinned ${CODEX_PINNED_VERSION}; reinstalling..."
  fi
  bashio::log.info "Installing Codex standalone runtime (pinned ${CODEX_PINNED_VERSION})..."
  env HOME="${HOME_DIR}" CODEX_HOME="${HOME_DIR}/.codex" USER="${USER_NAME}" \
    CODEX_NON_INTERACTIVE=true CODEX_RELEASE="${CODEX_PINNED_VERSION}" \
    su-exec "${USER_NAME}" sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh | sh' || {
    bashio::log.warning "Standalone Codex install failed."
    return 1
  }
}

# codex remote-control status is preferred (reports the daemon's own view of health); if
# this Codex version doesn't support that subcommand, fall back to a process-name match.
remote_control_alive() {
  local status_json
  if status_json="$(run_as_codex "${STANDALONE_CODEX}" remote-control status --json 2>/dev/null)"; then
    echo "${status_json}" | grep -qiE '"status"[[:space:]]*:[[:space:]]*"(connected|running|bootstrapped)"'
    return $?
  fi
  pgrep -f "codex app-server.*--remote-control" >/dev/null 2>&1
}

# Opt-in SSH access (public-key only) for interactive shells / VS Code Remote-SSH; disabled
# unless ssh_authorized_keys is set, since password auth is never enabled and an empty key
# list would just open a port nobody can authenticate against.
ensure_ssh_server() {
  if ! bashio::config.has_value 'ssh_authorized_keys'; then
    bashio::log.info "ssh_authorized_keys not set; SSH access disabled."
    return 0
  fi

  mkdir -p "${SSH_HOST_KEY_DIR}" "${HOME_DIR}/.ssh"
  : > "${HOME_DIR}/.ssh/sshd.log"
  local key_type
  for key_type in rsa ecdsa ed25519; do
    local key_path="${SSH_HOST_KEY_DIR}/ssh_host_${key_type}_key"
    [[ -f "${key_path}" ]] || ssh-keygen -t "${key_type}" -f "${key_path}" -N "" -q
  done

  bashio::config 'ssh_authorized_keys' > "${SSH_AUTHORIZED_KEYS_FILE}"
  chmod 700 "${HOME_DIR}/.ssh"
  chmod 600 "${SSH_AUTHORIZED_KEYS_FILE}"
  chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.ssh" "${SSH_HOST_KEY_DIR}"

  cat > /etc/ssh/sshd_config_codex <<EOF
Port 2222
HostKey ${SSH_HOST_KEY_DIR}/ssh_host_rsa_key
HostKey ${SSH_HOST_KEY_DIR}/ssh_host_ecdsa_key
HostKey ${SSH_HOST_KEY_DIR}/ssh_host_ed25519_key
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers ${USER_NAME}
Subsystem sftp /usr/lib/ssh/sftp-server
PidFile ${HOME_DIR}/.ssh/sshd.pid
EOF

  /usr/sbin/sshd -f /etc/ssh/sshd_config_codex -D -e >>"${HOME_DIR}/.ssh/sshd.log" 2>&1 &
  local sshd_pid=$!
  sleep 1
  # sshd normally self-daemonizes (fork+detach); relying on fd redirection surviving that
  # internal fork is fragile, so we keep it in the foreground (-D) and background it ourselves
  if ! kill -0 "${sshd_pid}" 2>/dev/null; then
    bashio::log.warning "sshd exited immediately; last log lines:"
    tail -n 30 "${HOME_DIR}/.ssh/sshd.log" 2>/dev/null | while IFS= read -r line; do
      bashio::log.warning "[sshd] ${line}"
    done
    return 1
  fi
  # there is no syslog daemon in this image, so sshd's own auth decisions (-e above) would
  # otherwise go nowhere; stream them into the add-on log so auth failures are diagnosable
  # (BusyBox tail has no -F, only -f; -F silently exited immediately, dropping all logging)
  ( tail -n0 -f "${HOME_DIR}/.ssh/sshd.log" | while IFS= read -r line; do
      bashio::log.info "[sshd] ${line}"
    done & )
  bashio::log.info "SSH server listening on container port 2222 (public-key only, user '${USER_NAME}', pid ${sshd_pid})."
}

MODE="$(bashio::config 'mode')"
GIT_BRANCH="$(bashio::config 'git_branch')"
if bashio::config.has_value 'codex_version'; then
  CODEX_PINNED_VERSION="$(bashio::config 'codex_version')"
else
  CODEX_PINNED_VERSION="${DEFAULT_CODEX_VERSION}"
fi

ensure_standalone_codex || bashio::log.warning "Continuing without a working Codex install; commands below will fail."
[[ -x "${STANDALONE_CODEX}" ]] && ln -sf "${STANDALONE_CODEX}" /usr/local/bin/codex
ensure_ssh_server || true
# any prior app-server-control state is guaranteed stale after a fresh container start
# (its PID tracking refers to a process from a namespace that no longer exists); clearing
# it avoids "failed to read start time for pid-managed app server" errors from a stale entry
rm -rf "${APP_SERVER_CONTROL_DIR}"
bashio::log.info "Codex version: $("${STANDALONE_CODEX}" --version 2>/dev/null || echo unavailable)"
bashio::log.info "Mode: ${MODE}"
bashio::log.info "Persistent state: ${HOME_DIR}/.codex"
bashio::log.info "Project: ${PROJECT_DIR}"

if bashio::config.has_value 'git_repo' && [[ ! -e "${PROJECT_DIR}/.git" ]] && [[ -z "$(ls -A "${PROJECT_DIR}" 2>/dev/null)" ]]; then
  GIT_REPO="$(bashio::config 'git_repo')"
  # strip any embedded credentials (user:token@) before this ever reaches the log
  GIT_REPO_SAFE="$(echo "${GIT_REPO}" | sed -E 's#^(https?://)[^@/]*@#\1#')"
  bashio::log.info "Cloning ${GIT_REPO_SAFE} (${GIT_BRANCH})..."
  run_as_codex git clone --branch "${GIT_BRANCH}" --single-branch "${GIT_REPO}" "${PROJECT_DIR}" || \
    bashio::log.warning "Clone failed; continue setup and clone later."
fi

case "${MODE}" in
  login)
    bashio::log.info "Starting Codex device authentication."
    bashio::log.info "Complete the URL/code shown below, then change mode to 'pair'."
    run_as_codex "${STANDALONE_CODEX}" login --device-auth || \
      bashio::log.warning "Login did not complete; change mode to 'login' and restart to retry."
    bashio::log.info "Login step finished. Change mode to 'pair' and restart."
    idle_forever
    ;;

  pair)
    bashio::log.info "Starting managed Codex Remote Control daemon..."
    run_as_codex "${STANDALONE_CODEX}" remote-control start --json || \
      bashio::log.warning "Remote Control start failed; will retry from the watch loop."
    bashio::log.info "Requesting a manual pairing code..."
    run_as_codex "${STANDALONE_CODEX}" remote-control pair --json || \
      bashio::log.warning "Pair request failed; restart again in pair mode for a fresh code."
    bashio::log.info "Enter manualPairingCode in the mobile Codex Remote pairing flow."
    bashio::log.info "After pairing, change mode to 'run'."
    while true; do
      sleep 60
      if ! remote_control_alive; then
        bashio::log.warning "Remote app-server stopped; requesting managed restart."
        run_as_codex "${STANDALONE_CODEX}" remote-control start --json || true
      fi
    done
    ;;

  run)
    bashio::log.info "Ensuring managed Remote Control is running..."
    run_as_codex "${STANDALONE_CODEX}" remote-control start --json || \
      bashio::log.warning "Remote Control start failed; will retry from the watch loop."
    bashio::log.info "Codex Direct Remote is online."
    while true; do
      sleep 60
      if ! remote_control_alive; then
        bashio::log.warning "Remote app-server stopped; requesting managed restart."
        run_as_codex "${STANDALONE_CODEX}" remote-control start --json || true
      fi
    done
    ;;

  stop)
    run_as_codex "${STANDALONE_CODEX}" remote-control stop --json || true
    bashio::log.info "Stopped. Change mode before starting again."
    idle_forever
    ;;

  doctor)
    run_as_codex "${STANDALONE_CODEX}" doctor --json || true
    bashio::log.info "Diagnostics complete. Change mode before starting again."
    idle_forever
    ;;

  *)
    bashio::log.fatal "Unknown mode: ${MODE}"
    exit 2
    ;;
esac
