# Codex Direct Remote for HAOS

Runs OpenAI Codex directly as a headless Remote Control host inside a Home Assistant OS app/add-on.

No Mac, Windows PC, SSH bridge, or Codex Desktop host is required. The container connects outbound to OpenAI's Remote Control infrastructure so it can be paired as a second, independent environment from the ChatGPT mobile app's Codex Remote section — alongside any existing VPS-hosted Remote environment, each with its own Codex identity.

```text
ChatGPT / Codex mobile
        │  OpenAI Remote Control (outbound only)
        ▼
Home Assistant OS
        └── Codex Direct Remote app
             ├── Codex CLI + app-server
             ├── persistent Codex identity/auth
             └── persistent project workspace
```

## Example use case

Install [ha-mcp](https://github.com/homeassistant-ai/ha-mcp) alongside this add-on, point it at your local Home Assistant URL, then ask Codex to configure it as an MCP server. From then on, Codex can manage Home Assistant directly — writing automations, dashboards, and templates — through a chat session from the Codex/ChatGPT mobile app, with no other host or SSH bridge involved. Secure and convenient!

---

## Requirements

- A Home Assistant OS (or Supervised) host with internet egress.
- `amd64` or `aarch64` architecture (see `arch` in [config.yaml](codex_remote/config.yaml)).
- An OpenAI/ChatGPT account with Codex access, used to pair this instance as a **new, separate** Remote environment (do not reuse credentials/state from another host — see [Security notes](#security-notes)).

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Open the **⋮** menu (top right) → **Repositories**, and add this repository's URL (see [repository.yaml](repository.yaml) for the canonical name/URL).
3. Find **Codex Direct Remote** in the store and click **Install**.
4. Do not start it yet — configure it first (next section).

## Configuration

Set these under the add-on's **Configuration** tab:

| Option | Default | Description |
|---|---|---|
| `mode` | `run` | One of `login`, `pair`, `run`, `stop`, `doctor`. See [First-time setup](#first-time-setup) and [Modes reference](#modes-reference). |
| `git_repo` | _(unset)_ | Optional git URL. If `/data/project` is empty, it's cloned in automatically on startup. Leave unset to manage the project directory yourself. |
| `git_branch` | `main` | Branch used for that initial clone. |
| `ssh_authorized_keys` | _(unset)_ | Optional. One or more SSH public keys (one per line). Setting this enables an SSH server on container port 2222 for interactive/VS Code Remote-SSH access. Leave unset to keep SSH disabled entirely. |
| `codex_version` | _(unset, pins to the add-on's built-in default)_ | Optional. Overrides the pinned Codex CLI release without editing `run.sh`. The add-on detects a mismatch against the installed binary and reinstalls automatically. |

Notes:
- Don't put long-lived credentials in `git_repo`. If you must use an authenticated URL, treat it as a secret — it grants repo access to anyone who can read the add-on config.
- The add-on requests no special Home Assistant permissions: no host network, no privileged mode, no full access, no Supervisor API, no Docker socket (see `config.yaml`).

## First-time setup

Do these steps in order, changing `mode` and restarting the add-on between each one. This mirrors the flow in [DETAILS.md](codex_remote/DETAILS.md).

### 1. Log in (`mode: login`)

1. Set `mode: login`, save, and **Start** the add-on.
2. Open the add-on **Log** tab. Codex prints a device login URL and code.
3. Complete the login in a browser using the OpenAI/ChatGPT account you want this HAOS instance to use.
4. Once login succeeds, move to step 2.

### 2. Pair with the mobile app (`mode: pair`)

1. Set `mode: pair`, save, and **Restart** the add-on.
2. The add-on starts the managed Remote Control daemon and requests a manual pairing code.
3. Watch the **Log** tab for a JSON blob containing `"manualPairingCode": "..."`.
4. In the ChatGPT mobile app, open **Codex Remote → add environment → manual pairing** and enter that code.
5. The code is short-lived. If it expires before you enter it: leave `mode: pair`, **Restart** the add-on again, and use the fresh code immediately.
6. Once the HAOS environment shows up in the mobile app, move to step 3.

### 3. Run (`mode: run`)

1. Set `mode: run`, save, and **Restart** the add-on.
2. Leave it in this mode permanently. The add-on keeps the Remote Control app-server alive and restarts it if the process disappears.

## Everyday use

With `mode: run`, no further action is needed on the HAOS side — drive everything from the ChatGPT mobile app's Remote interface. The add-on:

- Persists Codex auth/identity/state in `/data/home/.codex` and your project files in `/data/project` across restarts and updates.
- Checks every 5 minutes that the Remote Control app-server is still alive, and asks Codex to restart it if not.
- Logs status lines (`Mode: run`, `Codex Direct Remote is online.`, etc.) to the add-on **Log** tab.

### Working with a project

- If `git_repo` was set before the first start and `/data/project` was empty, it's cloned automatically.
- Otherwise, use a Codex Remote session (once paired) to `git clone`/initialize the project directly inside `/data/project`, or set `git_repo`/`git_branch` and restart before the directory has any content.

## Modes reference

| Mode | What it does |
|---|---|
| `login` | Runs `codex login --device-auth`; prints a device URL/code to the log. Use once, then switch to `pair`. |
| `pair` | Starts the managed Remote Control daemon and requests a manual pairing code for the mobile app. Use until pairing succeeds, then switch to `run`. |
| `run` | Normal always-on mode. Ensures Remote Control is running and self-heals if the app-server process dies. |
| `stop` | Stops the managed Remote Control daemon and idles. Use to temporarily take this environment offline without uninstalling. |
| `doctor` | Runs `codex doctor --json` and prints diagnostics to the log, then idles. Use for troubleshooting. |

After using `stop` or `doctor`, change `mode` back to `run` (or another mode) and restart to resume normal operation.

## Troubleshooting

- **Pairing code expired**: restart while still in `mode: pair` to get a fresh code, and enter it right away.
- **Remote environment not responding / stuck daemon**: restart the add-on itself first — this kills any orphaned Codex processes while keeping `/data` intact. Then re-apply `mode: run`.
- **Diagnose Codex's own view of its environment**: set `mode: doctor`, restart, and read the log output.
- **Nothing shows in the log**: confirm the add-on is actually started (not just saved) and check **Supervisor → System** for outbound network connectivity issues.

## Updating the pinned Codex CLI version

Codex is installed exclusively via OpenAI's standalone installer at container startup (`codex remote-control` refuses to run against any other install method), pinned deliberately so a restart always reproduces a known-good release instead of silently picking up whatever is newest. To upgrade, set the `codex_version` option (see the table above) and restart — the add-on detects the version mismatch against the already-installed binary and reinstalls automatically. Without a fork, `codex_version` is the only supported way to change it; the built-in default in [run.sh](run.sh) only matters if you leave the option unset.

## SSH access (optional)

By default there is no SSH server. Setting `ssh_authorized_keys` enables one, for interactive shells or VS Code's Remote-SSH extension:

1. Paste one or more SSH **public** keys (never a private key) into `ssh_authorized_keys`, one per line, and restart the add-on.
2. Under **Settings → Add-ons → Codex Direct Remote → Network**, the add-on exposes container port `2222/tcp`; note (or change) the host port it's mapped to.
3. Connect as the unprivileged `codex` user, e.g. `ssh -p 2222 codex@<haos-ip>`. Files you edit under `/data/project` are already owned by `codex`. The pinned `codex` CLI is on `PATH`.
4. Only public-key auth is accepted — password and root login are both disabled in `sshd_config`. Host keys are generated once and persisted under `/data/home/.ssh_host_keys`, so they survive restarts/updates (no repeated "host key changed" warnings).

**VS Code Remote-SSH caveat**: this add-on runs on Alpine (musl libc), while VS Code's official remote server is built for glibc. The image includes `gcompat` (Alpine's glibc compatibility shim), and Remote-SSH connects successfully with it in practice — though Microsoft doesn't officially support Alpine remotes, so treat this as best-effort.

This opens an inbound port on your LAN; only enable it if you need direct shell access, and keep your private key secure.

## Home Assistant config access (optional capability)

Starting with this version, the add-on declares **read-only** access to Home Assistant's own `/config` directory, so a Codex session can inspect `configuration.yaml`, automations, etc. This is a real permission grant, not a runtime toggle: Home Assistant add-ons can't make `map` entries conditional on an option, so it's present for anyone who installs/updates to this version. If you don't want Codex to have any access to your HA config, stay on `0.6.0` or remove the `map` entry from your own fork. It is intentionally read-only — Codex cannot modify your HA configuration through this mount.

The mount point is `/homeassistant` inside the container (some HA/Supervisor versions expose it as `/homeassistant_config` instead — check with `ls /homeassistant /homeassistant_config` if one of them doesn't exist). Home Assistant mounts it `0700 root:root`, unreadable by the unprivileged `codex` user the add-on otherwise runs as, and it's a read-only bind mount so those permissions can't be relaxed with `chmod`/`setfacl` from inside the container.

The add-on works around this by mirroring it: at startup (and every 60s afterwards) a root-owned step copies the mount to `/data/ha_config_ro`, owned by and readable by `codex` with no elevation needed. Read it directly, e.g. `cat /data/ha_config_ro/configuration.yaml`. This mirror can lag up to ~60s behind the live HA config, and it's a snapshot, not a live view — for anything security-sensitive re-read it after a `sync_ha_config_mirror` cycle rather than trusting a cached copy blindly. The sync uses `rsync -a --delete` (only changed files touched, not a full rewrite each cycle) and excludes `.storage/` (HA's own internal auth tokens/state), the recorder database, `www/`, `tts/`, `media/`, and `backups/` — none of that is needed to read `configuration.yaml`/automations/scripts, and `.storage/` in particular is more sensitive than typical YAML config, so it's deliberately left out of what's exposed to the mirror.

A passwordless, unrestricted `sudo` grant for `codex` (`/etc/sudoers.d/codex`) is also present and works from an interactive SSH shell (e.g. `sudo cat /homeassistant/configuration.yaml`), but **not** from inside a Codex session's own tool calls — Codex's exec sandbox sets `no_new_privileges`, which silently blocks the setuid `sudo` binary from escalating there. Use the `/data/ha_config_ro` mirror from Codex sessions instead. Be aware the `sudo` grant itself is not scoped to just `/config`: it gives `codex` (and therefore anything running under it outside the sandbox, e.g. SSH) full root inside the container. That's consistent with this add-on's existing threat model (single-tenant, your own container, no host privileges or `full_access`), but remove the sudoers rule in your own fork if you want `codex` confined to its own permissions everywhere.

## Security notes

- Do not copy `.codex` from another Codex host into this add-on's `/data/home/.codex`. This HAOS instance is meant to be its own independent Remote Control identity, separate from any VPS or desktop Codex environment you already use.
- Treat `/data/home/.codex` as sensitive: it holds auth/identity state. Don't commit it to git or share it. It's intentionally *included* in Supervisor backups (so a restore doesn't force re-login/re-pairing) — treat backup archives as similarly sensitive.
- `/data/home/.ssh_host_keys` is excluded from backups (`backup_exclude` in [config.yaml](config.yaml)) since it auto-regenerates on next start; restoring an old backup will just cost a one-time "host key changed" SSH warning.
- By default, the add-on has no listening services and makes no use of its declared port — Codex only makes outbound connections to OpenAI's Remote Control infrastructure. Container port 2222 is always mapped for convenience, but nothing listens on it, and SSH itself is opt-in; see [SSH access](#ssh-access-optional). HA config access is opt-in at the install/update level; see above.

For the full architecture, security model, and design rationale, see [DETAILS.md](codex_remote/DETAILS.md). For a condensed mode reference, see [DOCS.md](codex_remote/DOCS.md).
