---
name: shell
description: Use when the user wants to send a shell command into Neovim terminal slots 1 through 4 from inside a Neovim-managed terminal session.
---

# Shell

Use this skill to inject shell commands into Neovim terminal slots `1` through `4`.

## Workflow

1. Confirm the target slot with `-t=<1..4>`.
2. Run `~/.config/nvim/codex/scripts/shell.sh` with the shell command to send.
3. If Neovim was restarted, let the script refresh its cached RPC server from `$NVIM`.

## Rules

- This must be run from inside a Neovim terminal. If `$NVIM` is missing, stop and report the error.
- The script caches the canonical Neovim RPC server in `~/.cache/codex-shell/nvim-rpc-server`.
- In Codex-hosted environments, run the command through an explicit outside-the-sandbox execution path because Neovim RPC uses a Unix socket and sandboxed `connect()` calls may be blocked.
- Do not guess the target server by newest socket when an exact socket is already known. Prefer the socket discovered from `$NVIM`, or the exact socket path the user provides.
- If RPC access fails, rerun the command outside the sandbox or with whatever elevated execution path the host provides.
- Quote the whole shell command when it contains pipes, redirects, `&&`, or other shell operators.

## Command

```bash
~/.config/nvim/codex/scripts/shell.sh -t=<1..4> "<shell command>"
```

Examples:

```bash
~/.config/nvim/codex/scripts/shell.sh -t=1 "ls -al"
~/.config/nvim/codex/scripts/shell.sh -t=2 "npm run dev"
```
