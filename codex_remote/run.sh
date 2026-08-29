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

CODEX_PINNED_VERSION="0.151.0"
STANDALONE_CODEX="${HOME_DIR}/.codex/packages/standalone/current/codex"

# codex remote-control refuses to run unless this installer-managed copy exists at a fixed
# CODEX_HOME path (separate from the npm-installed CLI used for login/doctor).
ensure_standalone_codex() {
  if [[ -x "${STANDALONE_CODEX}" ]]; then
    return 0
  fi
  bashio::log.info "Installing Codex standalone runtime (required by remote-control)..."
  env HOME="${HOME_DIR}" CODEX_HOME="${HOME_DIR}/.codex" USER="${USER_NAME}" \
    CODEX_NON_INTERACTIVE=true CODEX_RELEASE="${CODEX_PINNED_VERSION}" \
    su-exec "${USER_NAME}" sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh | sh' || {
    bashio::log.warning "Standalone Codex install failed; remote-control will not start."
    return 1
  }
}

MODE="$(bashio::config 'mode')"
GIT_BRANCH="$(bashio::config 'git_branch')"

bashio::log.info "Codex version: $(codex --version)"
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
    run_as_codex codex login --device-auth || \
      bashio::log.warning "Login did not complete; change mode to 'login' and restart to retry."
    bashio::log.info "Login step finished. Change mode to 'pair' and restart."
    idle_forever
    ;;

  pair)
    ensure_standalone_codex || true
    bashio::log.info "Starting managed Codex Remote Control daemon..."
    run_as_codex codex remote-control start --json || \
      bashio::log.warning "Remote Control start failed; will retry from the watch loop."
    bashio::log.info "Requesting a manual pairing code..."
    run_as_codex codex remote-control pair --json || \
      bashio::log.warning "Pair request failed; restart again in pair mode for a fresh code."
    bashio::log.info "Enter manualPairingCode in the mobile Codex Remote pairing flow."
    bashio::log.info "After pairing, change mode to 'run'."
    while true; do
      sleep 300
      if ! pgrep -f "codex app-server.*--remote-control" >/dev/null 2>&1; then
        bashio::log.warning "Remote app-server stopped; requesting managed restart."
        run_as_codex codex remote-control start --json || true
      fi
    done
    ;;

  run)
    ensure_standalone_codex || true
    bashio::log.info "Ensuring managed Remote Control is running..."
    run_as_codex codex remote-control start --json || \
      bashio::log.warning "Remote Control start failed; will retry from the watch loop."
    bashio::log.info "Codex Direct Remote is online."
    while true; do
      sleep 300
      if ! pgrep -f "codex app-server.*--remote-control" >/dev/null 2>&1; then
        bashio::log.warning "Remote app-server stopped; requesting managed restart."
        run_as_codex codex remote-control start --json || true
      fi
    done
    ;;

  stop)
    run_as_codex codex remote-control stop --json || true
    bashio::log.info "Stopped. Change mode before starting again."
    idle_forever
    ;;

  doctor)
    run_as_codex codex doctor --json || true
    bashio::log.info "Diagnostics complete. Change mode before starting again."
    idle_forever
    ;;

  *)
    bashio::log.fatal "Unknown mode: ${MODE}"
    exit 2
    ;;
esac
