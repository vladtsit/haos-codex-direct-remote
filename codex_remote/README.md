# Codex Direct Remote for HAOS

Runs OpenAI Codex directly as a headless Remote Control host inside a Home Assistant OS app/add-on.

No Mac, Windows PC, SSH bridge, or Codex Desktop host is required.

Persistent data:
- `/data/home/.codex` — Codex auth, daemon identity/state, conversations
- `/data/project` — project workspace

First-time setup:
1. Set `mode: login`; start; complete device login from logs.
2. Set `mode: pair`; restart; enter `manualPairingCode` in mobile Remote.
3. Set `mode: run`; restart and leave it there.

Do not copy `.codex` from another host. This second HAOS instance should have its own identity.
