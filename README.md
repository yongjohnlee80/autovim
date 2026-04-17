# Johno's Neovim Config

My Neovim configuration for [Omarchy](https://omarchy.com), purpose-built for TypeScript and Go development with Claude as a first-class citizen.

## Why This Exists

Some people meditate. Some do yoga. I open Neovim, fire up Claude, and write Go and TypeScript until the world makes sense again. This is my happy place -- a terminal where keystrokes are cheap, feedback loops are tight, and the AI pair programmer never judges my variable names.

There's a certain poetry to it: Go for when you want the compiler to hold your hand, TypeScript for when you want the type system to argue with you, and Claude for when you want someone to tell you that your approach is "interesting" before gently suggesting you rewrite the whole thing. Neovim ties it all together like the world's most opinionated glue.

I've tried other setups. I've clicked through menus. I've dragged and dropped. I've used mice like some kind of animal. But nothing beats the flow of modal editing, instant AI assistance, and a config that loads faster than you can say "VS Code is updating." If the terminal is home, this config is the furniture.

## What's Inside

- **[LazyVim](https://www.lazyvim.org/)** -- because life's too short to configure everything from scratch, but too long to use someone else's config without tweaking it
- **[claudecode.nvim](https://github.com/anthropics/claude-code/tree/main/packages/claudecode.nvim)** -- Claude Code integration, right in the editor. `<leader>ac` and you're pair programming with an AI that actually reads your code
- **LSP + Mason** -- language servers managed properly, so Go and TypeScript just work
- **Treesitter** -- syntax highlighting that understands your code, not just your brackets
- **[nvim-dap](https://github.com/mfussenegger/nvim-dap) + [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view) + [nvim-dap-go](https://github.com/leoluz/nvim-dap-go)** -- delve-powered Go debugging with a minimalist inspection panel. Breakpoints, step controls, watches, attach-to-process, and debug-test-under-cursor
- **`utils.worktree`** -- in-editor worktree switcher. Hops between repos/worktrees under the directory you opened nvim in, without killing your terminal buffers
- **`utils.go_test_env`** -- reads `.vscode/launch.json` and merges `buildFlags` / `env` / `envFile` into `<leader>dt` so VSCode and Neovim share one source of truth for test debugging. Cached per session
- **11 colorschemes** -- because choosing a theme is a form of self-expression (currently rotating through them like outfits)

## Key Bindings Worth Knowing

### Editing & Claude

| Binding | What It Does |
|---|---|
| `jk` | Escape insert mode (the only correct mapping) |
| `<leader>ac` | Toggle Claude Code |
| `<leader>as` | Send selection to Claude |
| `<leader>ab` | Add current buffer to Claude |
| `<leader>aa` | Accept Claude's diff |
| `<leader>ad` | Deny Claude's diff |

### Debugging (Go + delve)

| Binding | What It Does |
|---|---|
| `F9` | Continue / start a debug session |
| `F8` | Step over |
| `F7` | Step into |
| `F10` | Step out |
| `<leader>db` | Toggle breakpoint |
| `<leader>dB` | Conditional breakpoint |
| `<leader>dC` | Clear all breakpoints |
| `<leader>dc` | Continue |
| `<leader>dr` | Run last |
| `<leader>dq` | Terminate session |
| `<leader>dR` | Restart |
| `<leader>dv` | Toggle dap-view inspection panel |
| `<leader>dw` | Add watch expression (also visual) |
| `<leader>de` | Evaluate under cursor / selection |
| `<leader>da` | Attach to a running process with delve |
| `<leader>dt` | Debug the Go test under cursor (merges `launch.json`) |
| `<leader>dT` | Re-run the last debug session |
| `<leader>dL` | Reload the cached `launch.json` |

### Worktree switching

| Binding | What It Does |
|---|---|
| `<leader>gw` | Pick a worktree under the root and `:cd` into it |
| `<leader>gW` | Jump back to the original root directory |

## Debugging Go Tests Like a Grown-up

The `<leader>dt` keymap doesn't just launch delve -- it reads `.vscode/launch.json` from your project root, pulls out `buildFlags`, `env`, and `envFile`, and passes them to the delve test run. Same file VSCode reads, so teammates on either editor share one config. The parsed values are cached for the nvim session (press `<leader>dL` to reload after editing).

Scaffolding the `launch.json` is a one-liner: run the `/go-test-env` Claude skill, answer a couple of prompts for build tags and env vars, and it writes strict JSON to `./.vscode/launch.json` (or wherever you point it). Existing Go configurations with the same name are replaced in place; everything else is preserved.

Typical flow:

1. `/go-test-env` -- prompts for `-tags=integration,gold`, `TEST_PGURL`, etc. Writes launch.json.
2. Open the test file, drop a breakpoint with `<leader>db`, cursor inside the test.
3. `<leader>dt` -- delve launches with the merged env, breakpoint hits, dap-view pops open.
4. `<leader>de` on any expression to live-evaluate. `<leader>dw` to watch something across frames.
5. `<leader>dT` re-runs with the same config. `<leader>dq` terminates.

## Worktree Switching Without Rage

If the directory you opened nvim in contains multiple git repos (or a bare repo with a pile of linked worktrees), `<leader>gw` fans them all out in a picker. Pick one -- nvim's cwd changes, a notification confirms the hop, and you're ready to go. `<leader>gW` takes you home.

Existing `:term` buffers **keep their own pwd**. That's not magic; it's just how POSIX processes work -- each shell inherited nvim's cwd at spawn time and is now an independent process. So your long-running `go test -watch` in terminal A doesn't get yanked around when you jump to a different repo in terminal B.

The picker uses `git worktree list --porcelain` under the hood, so both plain repos and bare-repo layouts with linked worktrees are handled. Bare repos themselves are skipped (you don't cd into those). Branch names show up in brackets; the active cwd gets a `●` marker.

## The Stack

```
Neovim + LazyVim
├── Go (the language that says "no" so you don't have to)
├── TypeScript (the language that says "any" when you give up)
└── Claude (the AI that says "have you considered..." before saving your afternoon)
```

## License

[MIT](LICENSE) -- take what you want, blame no one.
