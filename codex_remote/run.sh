\
#!/usr/bin/with-contenv bashio
set -euo pipefail

USER_NAME="codex"
HOME_DIR="/data/home"
PROJECT_DIR="/data/project"

mkdir -p "${HOME_DIR}/.codex" "${PROJECT_DIR}"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}" "${PROJECT_DIR}"

run_as_codex() {
  su -s /bin/bash "${USER_NAME}" -c \
    "export HOME='${HOME_DIR}' CODEX_HOME='${HOME_DIR}/.codex' USER='${USER_NAME}'; cd '${PROJECT_DIR}'; $*"
}

MODE="$(bashio::config 'mode')"
GIT_REPO="$(bashio::config 'git_repo')"
GIT_BRANCH="$(bashio::config 'git_branch')"

bashio::log.info "Codex version: $(codex --version)"
bashio::log.info "Mode: ${MODE}"
bashio::log.info "Persistent state: ${HOME_DIR}/.codex"
bashio::log.info "Project: ${PROJECT_DIR}"

if [[ -n "${GIT_REPO}" ]] && [[ ! -e "${PROJECT_DIR}/.git" ]] && [[ -z "$(ls -A "${PROJECT_DIR}" 2>/dev/null)" ]]; then
  bashio::log.info "Cloning ${GIT_REPO} (${GIT_BRANCH})..."
  run_as_codex "git clone --branch '${GIT_BRANCH}' --single-branch '${GIT_REPO}' '${PROJECT_DIR}'" || \
    bashio::log.warning "Clone failed; continue setup and clone later."
fi

case "${MODE}" in
  login)
    bashio::log.info "Starting Codex device authentication."
    bashio::log.info "Complete the URL/code shown below, then change mode to 'pair'."
    exec su -s /bin/bash "${USER_NAME}" -c \
      "export HOME='${HOME_DIR}' CODEX_HOME='${HOME_DIR}/.codex' USER='${USER_NAME}'; codex login --device-auth"
    ;;

  pair)
    bashio::log.info "Starting managed Codex Remote Control daemon..."
    run_as_codex "codex remote-control start --json"
    bashio::log.info "Requesting a manual pairing code..."
    run_as_codex "codex remote-control pair --json" || \
      bashio::log.warning "Pair request failed; restart again in pair mode for a fresh code."
    bashio::log.info "Enter manualPairingCode in the mobile Codex Remote pairing flow."
    bashio::log.info "After pairing, change mode to 'run'."
    while true; do
      sleep 300
      if ! pgrep -f "codex app-server.*--remote-control" >/dev/null 2>&1; then
        bashio::log.warning "Remote app-server stopped; requesting managed restart."
        run_as_codex "codex remote-control start --json" || true
      fi
    done
    ;;

  run)
    bashio::log.info "Ensuring managed Remote Control is running..."
    run_as_codex "codex remote-control start --json"
    bashio::log.info "Codex Direct Remote is online."
    while true; do
      sleep 300
      if ! pgrep -f "codex app-server.*--remote-control" >/dev/null 2>&1; then
        bashio::log.warning "Remote app-server stopped; requesting managed restart."
        run_as_codex "codex remote-control start --json" || true
      fi
    done
    ;;

  stop)
    run_as_codex "codex remote-control stop --json" || true
    bashio::log.info "Stopped. Change mode before starting again."
    sleep infinity
    ;;

  doctor)
    run_as_codex "codex doctor --json" || true
    bashio::log.info "Diagnostics complete. Change mode before starting again."
    sleep infinity
    ;;

  *)
    bashio::log.fatal "Unknown mode: ${MODE}"
    exit 2
    ;;
esac
