# Changelog

All notable changes to this add-on are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.7.0

### Added
- `icon.png` at the add-on root (Supervisor store/info page icon).
- `apparmor.txt`: a custom AppArmor profile (first pass, not yet verified against real hardware — disable via `apparmor: false` in `config.yaml` or delete the file if it causes unexpected denials).
- `codex_version` config option to override the pinned Codex CLI release without editing `run.sh`.
- Read-only access to Home Assistant's own `/config` (`map: homeassistant_config, read_only: true`). This is an install/update-time permission grant, not a runtime toggle — see README's "Home Assistant config access" section.
- `backup_exclude` for `home/.ssh_host_keys/**` (auto-regenerates; excluding it avoids storing private host keys in every Supervisor backup with no real backup value).

### Fixed
- Codex CLI version pin was only applied on first install; changing the pin (or now, `codex_version`) had no effect on an already-provisioned `/data`. The add-on now compares the installed binary's version against the pin on every startup and reinstalls on a mismatch.
- `sshd.log` grew unbounded across restarts; it is now truncated each time the SSH server is (re)started.
- Stale `app-server-control` state (from a previous container lifetime) could cause `remote-control start` to fail with "failed to read start time for pid-managed app server"; this state is now cleared on every startup.

### Changed
- Base image is now pinned to `ghcr.io/home-assistant/base:3.24-2026.08.0` instead of `:latest`, for reproducible builds (Supervisor's old `build.yaml`/`BUILD_FROM` mechanism is deprecated as of Supervisor 2026.04.0).
- The `pair`/`run` watch loops now use `codex remote-control status --json` to check daemon health (falling back to the previous `pgrep` process match if that subcommand isn't supported), and poll every 60s instead of every 300s.
- Corrected README wording that claimed "no inbound ports" — container port 2222 is always mapped, but nothing listens on it unless `ssh_authorized_keys` is set.

## 0.6.0

### Added
- This `CHANGELOG.md`, shown by Home Assistant Supervisor on the add-on's info page and in the update dialog.

## 0.5.8

### Removed
- Diagnostic-only debug logging added while troubleshooting SSH (authorized_keys fingerprint dump, path ownership dump, `sshd` `LogLevel DEBUG3`, `StrictModes no`) — no longer needed now that the root cause is fixed.

## 0.5.7

### Fixed
- SSH public-key login was rejected for the `codex` user because `adduser -D` leaves the account "locked" (shadow password prefixed with `!`), and `sshd` refuses login for locked accounts regardless of auth method. The account is now unlocked with `passwd -d` while password login stays disabled via `sshd_config`.

## 0.5.6

### Changed
- `sshd` now runs in the foreground (`-D`) and is backgrounded by the add-on itself, instead of relying on `sshd`'s own daemonizing fork to preserve log-file redirection.

## 0.5.4 – 0.5.5

### Fixed
- SSH auth log streaming produced no output because BusyBox `tail` doesn't support `-F` (only `-f`).

## 0.5.3

### Added
- Stream `sshd`'s own authentication log into the add-on log (this image has no syslog daemon), to make public-key auth failures diagnosable.

## 0.5.1 – 0.5.2

### Added
- Startup logging of the configured `ssh_authorized_keys` fingerprint and `/data` path ownership/permissions, to help verify SSH key setup.

## 0.5.0

### Added
- Optional SSH server (public-key only) on container port 2222 for interactive shell / VS Code Remote-SSH access, enabled by setting `ssh_authorized_keys`.

## 0.4.0

### Changed
- Consolidated Codex install to the standalone installer only, removing the npm-based install path. This closes a bug where npm's own copy could silently auto-update past the pinned `CODEX_PINNED_VERSION`.

## 0.3.0

### Fixed
- Version bump to force Supervisor to pick up the standalone-install fix (a repository refresh + version bump is required for Supervisor to fetch new commits).

## 0.2.0

### Added
- Initial Codex Direct Remote add-on: headless OpenAI Codex Remote Control host for Home Assistant OS, with `login` / `pair` / `run` / `stop` / `doctor` modes and optional `git_repo` project cloning.
