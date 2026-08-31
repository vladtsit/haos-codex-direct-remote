# Changelog

All notable changes to this add-on are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
