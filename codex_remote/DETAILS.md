# Codex Direct Remote for Home Assistant OS

## Overview

This Home Assistant OS app runs OpenAI Codex directly as a headless Remote Control environment.

It is designed for users who already use Codex Remote from the ChatGPT mobile app and want an additional independent Codex environment hosted on the same physical machine as Home Assistant OS.

The intended setup is:

```text
ChatGPT / Codex mobile
        │
        │ OpenAI Remote Control
        ▼
Home Assistant OS
        │
        └── Codex Direct Remote app
             │
             ├── OpenAI Codex CLI
             ├── Codex app-server
             ├── persistent Codex identity/auth
             └── persistent Project 2 workspace
```

No Mac or Windows desktop host is required.

No SSH bridge is required.

No inbound Internet port is required for Codex Remote itself.

The Codex process connects outbound to OpenAI's Remote Control infrastructure.

---

# Purpose

This app is intended to create a second independent Codex Remote environment.

For example:

```text
Mobile Codex Remote

├── Project 1
│   └── Ubuntu VPS
│       └── Codex Remote
│
└── Project 2
    └── Home Assistant OS
        └── Codex Direct Remote app
```

Each environment keeps its own Codex state and project files.

The Home Assistant environment must NOT reuse or copy the `.codex` directory from the existing VPS.

---

# Current Codex version

The app currently pins:

```text
codex-cli 0.151.0
```

This version was selected because it matches the known-working Linux VPS environment.

Codex is installed exclusively through OpenAI's standalone installer, run at container startup (not via npm in the Dockerfile), because `codex remote-control` refuses to run against any other install method. The pin's default lives in `run.sh`:

```bash
DEFAULT_CODEX_VERSION="0.151.0"
```

It can be overridden per-install via the `codex_version` config option (see [README.md](../README.md)) without editing this file. On startup, the add-on compares the installed binary's version against the pin and reinstalls automatically on a mismatch.

Do not upgrade Codex until the second Remote environment is confirmed working.

Once the environment is stable, the pinned version can be updated deliberately via `codex_version`.

---

# Persistent directories

The app uses Home Assistant app `/data` storage.

The important persistent paths are:

```text
/data/home/.codex
/data/project
```

## `/data/home/.codex`

This contains Codex-specific state.

Depending on the Codex release, it may contain:

* authentication state
* configuration
* Remote Control identity
* app-server metadata
* package metadata
* session information
* cached Codex runtime components

Treat this directory as sensitive.

Do not commit it to Git.

Do not publish it.

Do not copy it from another Codex host.

## `/data/project`

This is the Project 2 working directory.

Example:

```text
/data/project
├── .git
├── package.json
├── src
├── tests
└── README.md
```

Codex commands are started with this directory as the working directory.

---

# Linux user

The app creates a dedicated unprivileged user:

```text
codex
```

The important environment variables are:

```text
HOME=/data/home
CODEX_HOME=/data/home/.codex
USER=codex
```

This ensures that Codex writes persistent user data into Home Assistant app storage instead of the temporary container filesystem.

---

# Security model

The app deliberately does not request broad Home Assistant permissions.

The configuration includes:

```yaml
host_network: false
privileged: []
full_access: false
```

The app does not intentionally receive:

```text
Supervisor API
Docker socket
host filesystem
root access to HAOS
```

As of this version, the app does declare **read-only** access to Home Assistant's own `/config` (via `map: homeassistant_config, read_only: true` in `config.yaml`), mounted at `/homeassistant` inside the container (some Supervisor versions use `/homeassistant_config` instead). Home Assistant's add-on model has no runtime on/off switch for `map` entries — the grant applies to anyone who installs/updates to this version. See README's "Home Assistant config access" section for the full rationale and how to opt out (stay on an earlier version, or remove the entry in a fork).

That mount is `0700 root:root` on the host side, unreadable by the unprivileged `codex` user, and can't be relaxed via `chmod`/`setfacl` since it's read-only. A root-owned startup/periodic step (`sync_ha_config_mirror` in `run.sh`) instead copies it to `/data/home/ha_config_ro` (`~/ha_config_ro`), chowned to `codex`, refreshed every ~60s via `rsync -a --delete` (so the periodic refresh only touches changed files) with `.storage/`, the recorder database, `www/`, `tts/`, `media/`, and `backups/` excluded (large and/or more sensitive than typical YAML config, not needed to read it). A plain read of `/data/home/ha_config_ro` needs no privilege escalation, which matters because Codex's own tool calls run inside its exec sandbox (`no_new_privileges`), where the also-present passwordless `sudo` grant (`/etc/sudoers.d/codex`) is silently blocked from escalating (it does work over plain SSH, which isn't inside that sandbox). Deliberately not fixed by letting the sandbox allow `sudo` instead: that grant is unrestricted (`ALL=(ALL) NOPASSWD:ALL`), so allowing it through the sandbox would let any model-issued command — including one triggered by injected content in something it merely reads — escalate to full root with no approval step. See README for the full tradeoff.

The intended security boundary is:

```text
Home Assistant OS
│
├── Home Assistant Core
│
├── other apps
│
└── Codex Direct Remote
     └── /data
          ├── home
          └── project
```

Codex should only work inside its own container and project storage.

Do not add privileged mode or full host access unless you explicitly understand the security consequences.

---

# Network model

No inbound port is required for Codex Remote Control itself — the container always connects outbound to OpenAI's infrastructure regardless of any other setting.

An optional SSH server (public-key only) can be enabled by setting `ssh_authorized_keys`; see README's [SSH access](../README.md#ssh-access-optional) section. It is disabled by default, and even when the container port is mapped, nothing listens on it until a key is configured.

There is no web terminal.

The expected network model is:

```text
Codex container
      │
      │ outbound
      ▼
OpenAI services
```

The container therefore requires normal outbound Internet connectivity.

Do not expose arbitrary ports from the add-on to the public Internet unless you have a separate reason to do so.

---

# Configuration options

The app exposes:

```yaml
mode: run
git_repo: ""
git_branch: main
```

## `mode`

Supported modes are:

```text
login
pair
run
stop
doctor
```

Each mode is explained below.

## `git_repo`

Optional repository URL.

If `/data/project` is empty and `git_repo` is configured, the app attempts an initial clone.

Example:

```yaml
git_repo: "https://github.com/example/project2.git"
```

For private repositories, do not put long-lived credentials directly into this field.

## `git_branch`

Branch used during the optional initial clone.

Example:

```yaml
git_branch: main
```

---

# Mode: login

Use:

```yaml
mode: login
```

for first-time authentication.

The app runs:

```bash
codex login --device-auth
```

The Home Assistant app log should show a device login URL and code.

Complete the login using the same OpenAI / ChatGPT account that you use in the mobile app.

After successful login, authentication state is stored under:

```text
/data/home/.codex
```

Once authentication succeeds, change the mode to:

```yaml
mode: pair
```

and restart the app.

---

# Mode: pair

Use:

```yaml
mode: pair
```

when adding this HAOS machine as a new Remote environment.

The app first runs:

```bash
codex remote-control start --json
```

and then:

```bash
codex remote-control pair --json
```

The second command should print a short-lived manual pairing code.

Look in the Home Assistant app log for something similar to:

```json
{
  "manualPairingCode": "ABCD-EFGH"
}
```

The actual output may contain additional fields.

Open the Codex Remote section in the ChatGPT mobile app and use the manual pairing workflow to enter this code.

The pairing code is temporary.

If it expires:

1. keep `mode: pair`
2. restart the app
3. wait for a new code
4. enter the new code immediately

After pairing succeeds and the HAOS environment appears in the mobile Remote interface, change the mode to:

```yaml
mode: run
```

and restart the app.

---

# Mode: run

This is the normal permanent operating mode.

Use:

```yaml
mode: run
```

The app runs:

```bash
codex remote-control start --json
```

This asks Codex to start its managed Remote Control app-server.

The expected process pattern is similar to:

```text
codex app-server daemon pid-update-loop
codex app-server --remote-control --listen unix://
```

The exact process arguments may change between Codex releases.

The app keeps running and periodically checks that a Remote Control app-server process still exists.

If the process disappears, the script asks Codex to start Remote Control again.

For normal use, leave the app permanently in:

```yaml
mode: run
```

---

# Mode: stop

Use:

```yaml
mode: stop
```

to explicitly stop Codex Remote Control.

The app runs:

```bash
codex remote-control stop --json
```

This mode is useful for troubleshooting stale daemon state.

A typical recovery sequence is:

```text
mode: stop
restart app
wait for stop confirmation
stop app
change mode to run
start app
```

Because the Home Assistant app container is restarted, orphaned processes disappear while `/data` remains persistent.

---

# Mode: doctor

Use:

```yaml
mode: doctor
```

for diagnostics.

The app attempts to run:

```bash
codex doctor --json
```

Diagnostic output is printed into the Home Assistant app log.

After collecting the output, switch back to:

```yaml
mode: run
```

and restart.

---

# First-time setup

Follow this sequence exactly.

## Step 1 — Install the app

Add the custom app repository to Home Assistant and install:

```text
Codex Direct Remote
```

Do not start it in normal run mode yet.

## Step 2 — Configure login mode

Set:

```yaml
mode: login
git_repo: ""
git_branch: main
```

Save the configuration.

Start the app.

Open the Log tab.

## Step 3 — Authenticate

Complete the device authentication shown in the app log.

Use the same ChatGPT/OpenAI account that is logged into the mobile Codex Remote interface.

Do not copy `.codex` from another machine.

## Step 4 — Stop the app

After login succeeds, stop the app.

## Step 5 — Change to pair mode

Set:

```yaml
mode: pair
git_repo: ""
git_branch: main
```

Save.

Start the app.

## Step 6 — Read the pairing code

Look for the output from:

```bash
codex remote-control pair --json
```

Copy the `manualPairingCode`.

## Step 7 — Pair from mobile

Open ChatGPT / Codex Remote on your phone.

Add another machine or environment.

Enter the pairing code.

After successful pairing, confirm that both environments are visible.

Expected result:

```text
Remote
├── Project 1 / VPS
└── Project 2 / HAOS
```

The exact names may differ.

## Step 8 — Change to permanent run mode

Set:

```yaml
mode: run
git_repo: ""
git_branch: main
```

Save.

Restart the app.

## Step 9 — Enable automatic startup

Enable:

```text
Start on boot
```

If Home Assistant provides a Watchdog option for this app, it is also reasonable to enable it.

---

# Adding Project 2

The project directory is:

```text
/data/project
```

There are two supported approaches.

## Automatic initial clone

Configure:

```yaml
mode: run
git_repo: "https://github.com/example/project2.git"
git_branch: main
```

If `/data/project` is empty, the startup script attempts:

```bash
git clone --branch main --single-branch REPOSITORY /data/project
```

The clone is only attempted when the project directory is empty.

Existing project contents are not overwritten.

## Manual repository setup

You may also leave:

```yaml
git_repo: ""
```

and let Codex configure or clone the repository after Remote Control is working.

This is often preferable for private repositories.

---

# Private Git repositories

Do not embed personal access tokens into:

```yaml
git_repo:
```

For example, avoid:

```text
https://username:token@github.com/example/private-project.git
```

because that exposes credentials through Home Assistant configuration and logs.

Preferred approaches include:

```text
GitHub deploy key
dedicated SSH key
GitHub App credential
short-lived credential
```

A future revision of the app can add dedicated persistent Git SSH-key management.

---

# Do not copy the VPS Codex state

Your existing Project 1 host may have:

```text
/home/ubuntu/.codex
```

Do not copy this directory into HAOS.

The HAOS instance must create its own:

```text
/data/home/.codex
```

The desired state is:

```text
VPS
└── Codex Remote identity A
```

and:

```text
HAOS
└── Codex Remote identity B
```

Both can belong to the same ChatGPT account.

This separation is important for maintaining two independent Remote environments.

---

# Expected processes

On a healthy Remote Control host, Codex may run processes similar to:

```text
codex app-server daemon pid-update-loop
```

and:

```text
codex app-server --remote-control --listen unix://
```

The app intentionally uses:

```bash
codex remote-control start
```

instead of directly launching `codex app-server`.

This allows Codex itself to manage the Remote Control daemon lifecycle.

---

# Container restarts

The app container filesystem is disposable.

The `/data` directory is persistent.

Therefore a restart should behave like:

```text
container processes
    → recreated

temporary container files
    → recreated

/data/home/.codex
    → preserved

/data/project
    → preserved
```

This makes a full app restart a useful way to clear orphaned Codex processes without losing login state or project files.

---

# Home Assistant reboot behavior

When `Start on boot` is enabled:

```text
HAOS boots
   ↓
Supervisor starts Codex Direct Remote
   ↓
run.sh starts
   ↓
codex remote-control start
   ↓
Codex reconnects
   ↓
Remote environment becomes available
```

Normally you should not need to manually pair again after every HAOS restart.

---

# Troubleshooting

## App starts but Remote environment is offline

First restart the app.

If that does not help:

```text
1. set mode: stop
2. restart
3. wait for stop confirmation
4. stop app
5. set mode: run
6. start app
```

## Authentication error

Set:

```yaml
mode: login
```

Restart and perform device authentication again.

After authentication, switch back to:

```yaml
mode: run
```

If the Remote pairing identity remains valid, re-pairing may not be required.

## Pairing code expired

Leave:

```yaml
mode: pair
```

Restart the app.

A new pairing code should be generated.

## Pairing succeeds but Project 1 disappears

Do not copy files or credentials between hosts.

Do not delete either `.codex` directory.

Capture:

```text
HAOS pair logs
mobile Remote screen behavior
codex remote-control start --json output
codex remote-control pair --json output
```

This could indicate an account-level or client-level limitation around multiple paired environments.

## Remote daemon disappears repeatedly

Use:

```yaml
mode: doctor
```

and inspect the logs.

Also verify that the HAOS machine has:

```text
working DNS
outbound HTTPS access
correct system time
sufficient RAM
sufficient disk space
```

---

# Resource recommendations

Codex itself is not necessarily heavy while idle, but development workloads may be.

Typical tasks can include:

```text
npm install
Python package installation
compilation
tests
repository indexing
large file searches
build processes
database migration tools
```

A practical HAOS host for light-to-medium development should ideally have at least:

```text
4 CPU cores
8 GB RAM
SSD storage
```

A more comfortable system is:

```text
4–8 CPU cores
16 GB RAM
SSD/NVMe
```

Avoid running heavy development workloads if Home Assistant is already memory- or CPU-constrained.

Home automation reliability should take priority over development workloads.

---

# Storage considerations

Watch the size of:

```text
/data/project
```

especially for projects containing:

```text
node_modules
Python virtual environments
build artifacts
large dependency caches
Docker-like generated files
large datasets
```

Also monitor:

```text
/data/home/.codex
```

for growth over time.

---

# Backups

Project source code should normally be backed up through Git.

Codex state can also be covered by Home Assistant backups, but remember:

```text
/data/home/.codex
```

may contain sensitive authentication information.

Treat backups containing this directory like credentials.

Do not publish them.

---

# Updating the app

When modifying the Dockerfile or scripts, increment:

```yaml
version:
```

in:

```text
codex_remote/config.yaml
```

Example:

```yaml
version: "0.2.1"
```

Push the changes to the custom repository.

Refresh Home Assistant's app store and update/rebuild the app.

Persistent `/data` should remain intact across updates.

---

# Updating Codex

Do not automatically follow latest while initially validating the setup.

Current pin, in `run.sh`:

```bash
CODEX_PINNED_VERSION="0.151.0"
```

To upgrade later:

```bash
CODEX_PINNED_VERSION="NEW_VERSION"
```

Then increment the app version.

Recommended process:

```text
1. confirm Project 1 works
2. confirm Project 2 works
3. record current versions
4. upgrade one environment
5. test Remote
6. upgrade the other environment
```

This makes rollback easier if Remote Control behavior changes.

---

# Recommended normal configuration

After setup is complete:

```yaml
mode: run
git_repo: ""
git_branch: main
```

Leaving `git_repo` empty after initial project setup keeps Git operations separate from app startup.

---

# Final expected topology

```text
                         ChatGPT mobile
                               │
                         Codex Remote
                           /        \
                          /          \
                         ▼            ▼
                  Remote Host 1   Remote Host 2
                         │            │
                         ▼            ▼
                   Ubuntu VPS        HAOS
                         │            │
                    Codex CLI    Codex Direct
                      0.151.0      Remote app
                         │            │
                         ▼            ▼
                     Project 1     Project 2
```

Each host has:

```text
independent Codex state
independent Remote identity
independent project workspace
```

while both are authenticated to the same ChatGPT account.

---

# Deployment checklist

Before considering the installation complete, verify:

```text
[ ] App installs successfully
[ ] codex --version reports 0.151.0
[ ] device login succeeds
[ ] /data/home/.codex persists across restart
[ ] remote-control start succeeds
[ ] manual pairing code is generated
[ ] mobile app accepts pairing code
[ ] Project 1 remains visible
[ ] Project 2 appears as a second Remote environment
[ ] mode is changed to run
[ ] app survives restart
[ ] HAOS reboot automatically restores Remote
[ ] Project 2 files persist under /data/project
[ ] Home Assistant remains stable under development load
```

Once these checks pass, the HAOS machine is functioning as an independent headless Codex Remote host.
