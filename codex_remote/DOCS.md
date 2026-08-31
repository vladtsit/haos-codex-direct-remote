# Modes

- `login`: `codex login --device-auth`
- `pair`: starts managed Remote Control and emits a short-lived manual pairing code
- `run`: normal always-on operation
- `stop`: stops managed Remote Control
- `doctor`: prints `codex doctor --json`

The image installs Codex via OpenAI's standalone installer at container startup (required by `remote-control`), pinned by default to 0.151.0 in `run.sh`, overridable per-install with the `codex_version` option (auto-reinstalls on a version mismatch).

Optional SSH (public-key only, disabled unless `ssh_authorized_keys` is set) is available on container port 2222 for interactive shell / VS Code Remote-SSH access. See [README.md](../README.md).

Recovery:
If the daemon becomes stale/unmanaged, restart the Home Assistant app/container first.
That kills orphan processes while preserving `/data`. Then use `mode: run` again.
