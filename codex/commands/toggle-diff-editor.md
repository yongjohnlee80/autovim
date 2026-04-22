# /toggle-diff-editor

Turn the shared Neovim live patch-preview workflow on or off for the current conversation.

Usage:

```bash
/toggle-diff-editor on
/toggle-diff-editor off
```

Behavior when `on`:

- Prefer the shared live patch-preview / diff-editor workflow before applying non-trivial edits.
- In Neovim contexts, use the existing Codex patch flow backed by:
  - `~/.config/nvim/lua/utils/codex.lua`
  - `~/.config/nvim/plugin/codex.lua`
  - `~/.config/nvim/bin/codex-patch-review`
  - Use the same outside-the-sandbox rule as `/skills/shell`, because Neovim RPC uses a Unix socket and sandboxed `connect()` calls may be blocked.
  - When sending to a live Neovim session from outside the editor, target the exact requested socket instead of guessing by recency.
- Relevant review commands inside Neovim:
  - `:CodexPatch`
  - `:CodexPatchFile`
  - `:CodexPatchSelection`
  - `:CodexDiffAccept`
  - `:CodexDiffDeny`
  - `:CodexDiffRefresh`
- Fall back to normal direct editing if Neovim is unavailable, RPC is unavailable, or the user explicitly asks for immediate edits.

Behavior when `off`:

- Resume the normal Codex direct-edit workflow.
- Do not force the diff editor unless the user explicitly asks to preview the patch first.

Rules:

- Treat this as a conversation-scoped preference unless the user explicitly asks to persist it elsewhere.
- Open the review from a temporary patch buffer or patch file. Do not modify the target file until the patch is accepted.
- If live RPC is required, use an explicit outside-sandbox call rather than assuming the host will infer that automatically.
- Confirm the new state in one short sentence, then follow it.
