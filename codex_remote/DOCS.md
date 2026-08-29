# Modes

- `login`: `codex login --device-auth`
- `pair`: starts managed Remote Control and emits a short-lived manual pairing code
- `run`: normal always-on operation
- `stop`: stops managed Remote Control
- `doctor`: prints `codex doctor --json`

The image installs Codex via OpenAI's standalone installer at container startup (required by `remote-control`), pinned to 0.151.0 via `CODEX_PINNED_VERSION` in `run.sh` to match the known-working VPS.

Recovery:
If the daemon becomes stale/unmanaged, restart the Home Assistant app/container first.
That kills orphan processes while preserving `/data`. Then use `mode: run` again.
