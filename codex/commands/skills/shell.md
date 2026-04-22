# /skills/shell

Send a shell command into one of the numbered Neovim terminals.

Usage:

```bash
/skills/shell -t=1 ls -al
/skills/shell --term 2 "npm run dev"
/skills/shell -t=4 "go test ./..."
```

Rules:

- `-t` or `--term` is required and must be `1`, `2`, `3`, or `4`.
- This command must be run from inside a Neovim-managed terminal.
- In Codex-hosted environments, run it through an explicit outside-sandbox call so Unix socket RPC to Neovim is allowed.
- The Neovim RPC server is discovered once from `$NVIM`, then cached locally for reuse.
- If the exact socket path is already known, use that exact target instead of guessing from the newest Neovim process.
- If the cache is stale after a Neovim restart, it is refreshed automatically from `$NVIM`.

Command:

```bash
~/.config/nvim/codex/scripts/shell.sh -t=<1..4> "<shell command>"
```

For commands with pipes, redirects, or shell operators, quote the whole command string.

If you see an RPC connection error, rerun the command outside the sandbox.
