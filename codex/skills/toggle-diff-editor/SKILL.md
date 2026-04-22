---
name: toggle-diff-editor
description: Use when the user wants Codex to prefer or stop preferring the shared Neovim live patch-preview / diff editor workflow before applying code changes.
---

# Toggle Diff Editor

Use this skill when the user names `$toggle-diff-editor`, asks to use the live diff editor or patch preview, or asks to turn that behavior on or off.

## What It Controls

- `on`: prefer patch-first review through the shared Neovim Codex diff editor for substantial changes or when the user wants to inspect changes before they land.
- `off`: return to the normal direct-edit workflow.

## On Behavior

When enabled:

1. Prefer proposing an editable patch before applying non-trivial code changes.
2. In a Neovim-managed terminal, use the shared patch review flow already implemented in:
   - `~/.config/nvim/lua/utils/codex.lua`
   - `~/.config/nvim/plugin/codex.lua`
   - `~/.config/nvim/bin/codex-patch-review`
   - Use the same outside-the-sandbox rule as the `shell` skill, because Neovim RPC uses a Unix socket and sandboxed `connect()` calls may be blocked.
   - When driving a live Neovim instance from outside the editor, target the exact requested RPC socket. Do not assume the newest `/run/user/.../nvim.*` socket is the right one.
3. Use the Neovim Codex commands when they fit the task:
   - `:CodexPatch`
   - `:CodexPatchFile`
   - `:CodexPatchSelection`
   - `:CodexDiffAccept`
   - `:CodexDiffDeny`
   - `:CodexDiffRefresh`
4. Keep direct edits available as a fallback when preview mode is not practical.

## Off Behavior

When disabled:

1. Resume the standard Codex workflow of editing files directly.
2. Only use the patch preview flow if the user explicitly asks to review a patch first.

## Rules

- Treat the toggle as a conversation-scoped preference unless the user asks to persist it somewhere durable.
- Prefer the diff editor mainly for multi-file changes, risky edits, or explicit review requests; do not force it for every trivial one-line fix.
- If Neovim RPC is needed from a Codex-hosted environment, send the command through an explicit outside-the-sandbox execution path, as described by the `shell` skill.
- If multiple Neovim sockets exist, either use the exact socket the user identifies or verify the intended target before sending the patch review command.
- The review UI must open from a temporary patch buffer or patch file. Do not treat the target file buffer as already edited before the user accepts the patch.
- If Neovim, the RPC socket, or the patch-review command is unavailable, state that briefly and fall back to normal editing.
- If the user explicitly asks for immediate direct changes, follow that request even when the toggle is on.

## Command Reference

See:

```text
commands/toggle-diff-editor.md
```
