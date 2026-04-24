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
- **[worktree.nvim](https://github.com/yongjohnlee80/worktree.nvim)** -- in-editor worktree switcher I wrote. Hops between repos/worktrees under the directory you opened nvim in, with safety rails on add/remove and ghost-buffer cleanup. Comes with a lualine component and optional LSP re-anchor on switch
- **[gobugger.nvim](https://github.com/yongjohnlee80/gobugger.nvim)** -- another plugin I wrote. Opinionated Go debugger: launch.json-driven, worktree-aware, delve-integrated, dap-view as the UI. Picker with session cache, scaffolder for new test/main entries, doctor command for diagnosing build/worktree issues
- **[lazysql](https://github.com/jorgerojas26/lazysql)** -- a TUI SQL client hoisted into a floating window via `snacks.terminal`. Pre-configured connections, one keystroke to toggle, and the process stays alive between toggles so you don't pay the connection cost twice
- **[kulala.nvim](https://github.com/mistweaverco/kulala.nvim)** -- HTTP client driven by `.http` files. Replaced `rest.nvim` (whose luarocks build chain was miserable on macOS). Per-project scaffold under `.rest/` via `<leader>Rs`, a single gitignored `http-client.private.env.json` with generic keys (`BASE_URL`, `USER_NAME`, `USER_PASS`, `API_KEY`), and `<leader>Rr` / `<leader>Rl` / `<leader>Ra` to run / replay / run-all
- **[glow.nvim](https://github.com/ellisonleao/glow.nvim)** -- floating markdown preview powered by `charmbracelet/glow`. `<leader>mp` on any `*.md` file, full ANSI colors because I forced `CLICOLOR_FORCE=1` so termenv stops stripping them
- **Floating terminals via `snacks.terminal`** -- four toggleable floating terminals on `F1`–`F4`, each with its own persistent shell. Works from normal mode *and* terminal mode, so you can bounce between them without juggling `<C-\\><C-n>` every time
- **Codex Neovim bundle** -- a repo-local Codex wrapper plus bundled `shell` and `toggle-diff-editor` skills. `F5` toggles slot-5 Codex (safe by default), `<A-s>` / `<A-t>` swap slot 5 into safe / trusted mode, and the launcher prints a short welcome note with the diff-editor hint
- **11 colorschemes** -- because choosing a theme is a form of self-expression (currently rotating through them like outfits)

## Dependencies

One external binary this config relies on that doesn't install itself through Lazy or Mason:

- **`lazysql`** — the TUI SQL client wired to `<C-q>`. The Neovim side is just a `snacks.terminal` toggle; the binary has to be on your `$PATH`.

| Tool | Arch | macOS |
|---|---|---|
| `lazysql` | `yay -S lazysql-bin` (AUR) | `go install github.com/jorgerojas26/lazysql@latest` |

Connection setup for `lazysql` lives in [SQL Without Leaving Neovim](#sql-without-leaving-neovim).

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
| `<leader>Ac` | Toggle Codex (resume last session) |
| `<leader>AN` | Toggle Codex, forcing a fresh session |
| `<leader>As` | Replace slot 5 with safe-mode Codex (default) |
| `<leader>At` | Replace slot 5 with trusted-mode Codex |

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
| `<leader>da` | Attach to a local process via delve (PID picker; spawns dlv as a child) |
| `<leader>dA` | Attach to an already-running `dlv --headless --listen=:PORT` server. Prompts for port (default 2345). Pure connect-only adapter — no spawn race |
| `<leader>dt` | Debug the Go test under cursor (merges `launch.json`) |
| `<leader>dm` | Debug a main program via `mode=debug` config in `launch.json` |
| `<leader>dM` | Scaffold a new `mode=debug` entry into the project-root `launch.json` |
| `<leader>dN` | Scaffold a new `mode=test` entry into the project-root `launch.json` |
| `<leader>dD` | Doctor — report launch.json / worktree / git state |
| `<leader>dE` | Open the last failed-start stderr in a scratch buffer (auto-captured on `<leader>dm` / `<leader>dt` failure) |
| `<leader>dF` | Fix worktree — `git worktree repair` from the bare |
| `<leader>dL` | Reload the cached `launch.json` + clear session picks |

### Worktree switching

| Binding | What It Does |
|---|---|
| `<leader>gw` | Pick a worktree under the root and `:cd` into it |
| `<leader>gW` | Jump back to the original root directory |

### SQL (lazysql)

| Binding | What It Does |
|---|---|
| `<C-q>` | Toggle the lazysql float (works in normal and terminal mode) |

### Floating terminals

| Binding | What It Does |
|---|---|
| `F1` | Toggle Terminal 1 (works in normal and terminal mode) |
| `F2` | Toggle Terminal 2 |
| `F3` | Toggle Terminal 3 |
| `F4` | Toggle Terminal 4 |
| `F5` | Toggle Codex |

### Markdown

| Binding | What It Does |
|---|---|
| `<leader>mp` | Toggle glow markdown preview (markdown files only) |

## Go Debugging with gobugger.nvim

The `<leader>d*` bindings are backed by [gobugger.nvim](https://github.com/yongjohnlee80/gobugger.nvim), an opinionated Go debugger I extracted out of this config. `<leader>dt` / `<leader>dm` don't just launch delve — they read `launch.json` from your project, pull out `buildFlags`, `env`, `envFile` (and for main-program debug: `program`, `args`, `cwd`), feed the resolved config to the delve run, and open `dap-view` as the inspection UI. Same file VSCode reads, so teammates on either editor share one config.

**Multi-config picker.** If `launch.json` has more than one `type=go, mode=test` (or `mode=debug`) entry — e.g., one per `cmd/*` entry point, or separate test configs for different build tags — you get a `vim.ui.select` picker on first use. The pick is cached for the session, keyed independently per mode. `:Gobugger pick [test|debug]` clears just the pick; `<leader>dL` (or `:Gobugger reload`) clears the file cache AND all picks.

**Worktree-aware launch.json lookup.** Resolution walks upward from cwd, stopping at the first `.bare/` or `.git/` directory it encounters (project boundary). That means you can park one `launch.json` at the project root (next to `.bare/` or `.git/`) and every worktree inherits it — no copy-paste per branch. `${workspaceFolder}` still resolves to the current worktree's cwd, so `envFile = "${workspaceFolder}/.env"` gives each worktree its own env. A worktree-specific `.vscode/launch.json` overrides the shared one by winning the upward walk first.

**Scaffolding.** `<leader>dN` and `<leader>dM` scaffold new `mode=test` / `mode=debug` entries into the project-root `.vscode/launch.json` using the current buffer's package. Prompts for name, args (debug only), inline env (`KEY=VAL;KEY=VAL`), envFile, and buildFlags (pre-filled with `-buildvcs=false` because bare+worktree layouts break Go's VCS stamp).

**Doctor & fix.** `<leader>dD` dumps a diagnostic report — launch.json path, project root, cwd `.git` status, go module root, all available configs per mode. `<leader>dF` runs `git worktree repair` from the bare when gitfile pointers go stale.

**Failed-start error capture.** When `<leader>dm` / `<leader>dt` fail to initialize (missing binary, build error, bad args, etc.), gobugger captures the adapter's stderr / console output and surfaces it as a single ERROR notify with a 600-char preview. `<leader>dE` (or `:Gobugger last-error`) opens the full buffered output in a scratch buffer for scrolling — so you don't have to dig through `~/.cache/nvim/dap.log` to find out why delve refused to start.

**Two attach modes.** `<leader>da` is the PID-picker flow from `nvim-dap-go` — gobugger spawns dlv itself, attaches to a local process, and takes over. On Linux boxes with `/proc/sys/kernel/yama/ptrace_scope = 1` this needs either `sudo` or ptrace to be relaxed. `<leader>dA` complements it: when dlv was already started externally (`dlv attach <pid> --headless --listen=:2345 --accept-multiclient` in a sibling terminal, or `/run <app> --dlv`), `<leader>dA` prompts for the port and TCP-connects via a pure connect-only adapter. No subprocess, no race.

Typical test-debug flow:

1. Open a Go test file, drop a breakpoint with `<leader>db`, cursor inside the test.
2. `<leader>dt` — delve launches (falls back to dap-go defaults if no launch.json config exists), breakpoint hits, dap-view pops open.
3. `<leader>de` on any expression to live-evaluate. `<leader>dw` to watch something across frames.
4. `<leader>dr` re-runs with the same config. `<leader>dq` terminates.
5. If the session didn't start at all, `<leader>dE` pops the captured stderr open.

Typical main-debug flow (multi-entry-point repo):

1. `<leader>dM` in any `cmd/*/main.go` to scaffold a `mode=debug` entry (or edit `.vscode/launch.json` by hand).
2. `<leader>dm` — picker shows all main-program configs. Pick one; delve builds + launches it.
3. Subsequent `<leader>dm` presses in the same session reuse the pick (no prompt). `:Gobugger pick debug` to re-prompt.

## Worktree Switching Without Rage

If the directory you opened nvim in contains multiple git repos (or a bare repo with a pile of linked worktrees), `<leader>gw` fans them all out in a picker. Pick one -- nvim's cwd changes, a notification confirms the hop, and you're ready to go. `<leader>gW` takes you home.

Existing `:term` buffers **keep their own pwd**. That's not magic; it's just how POSIX processes work -- each shell inherited nvim's cwd at spawn time and is now an independent process. So your long-running `go test -watch` in terminal A doesn't get yanked around when you jump to a different repo in terminal B.

The picker uses `git worktree list --porcelain` under the hood, so both plain repos and bare-repo layouts with linked worktrees are handled. Bare repos themselves are skipped (you don't cd into those). Branch names show up in brackets; the active cwd gets a `●` marker.

## SQL Without Leaving Neovim

`<C-q>` drops [lazysql](https://github.com/jorgerojas26/lazysql) into a lazygit-style floating window. First press boots the picker with your configured connections; subsequent presses hide/show the float while the process keeps running in the background -- so reconnecting to prod is a one-time cost per nvim session.

**Requirements.** Install the binary on your system (pick your flavor: `yay -S lazysql-bin`, `go install github.com/jorgerojas26/lazysql@latest`, or grab a release from the repo). The nvim side is just a `snacks.terminal` toggle -- no plugin to install.

**Connections.** Connections live in `~/.config/lazysql/config.toml`. One `[[database]]` block per entry; lazysql reads the file on launch. Keep the file `chmod 600` since the URL embeds credentials.

```toml
[[database]]
Name = 'My Prod DB'
Provider = 'postgres'
DBName = 'myapp'
URL = 'postgresql://user:pass@host:5432/myapp'
ReadOnly = false

[[database]]
Name = 'Local'
Provider = 'postgres'
DBName = 'dev'
URL = 'postgresql://root:secret@localhost:5432/dev?sslmode=disable'
ReadOnly = false
```

Set `ReadOnly = true` on anything you'd rather not fat-finger a `DELETE` into. Supported providers include `postgres`, `mysql`, `sqlite3`, and a few others -- check the [lazysql repo](https://github.com/jorgerojas26/lazysql) for the full list.

**In-app keys worth knowing.** `?` opens lazysql's own help panel, but these are the ones you'll actually use:

| Key | What It Does |
|---|---|
| `H` / `L` | Focus sidebar / focus table |
| `j` / `k` | Move down / up |
| `/` | Filter / search |
| `c` | Edit cell |
| `o` | Insert new row |
| `d` | Delete row |
| `y` | Yank cell value |
| `Ctrl+E` | Open the SQL editor |
| `Ctrl+R` | Execute query |
| `Ctrl+S` | Save pending changes |
| `<` / `>` | Previous / next page |
| `J` / `K` | Sort descending / ascending |
| `z` / `Z` | Toggle JSON viewer for cell / row |
| `E` | Export to CSV |
| `?` | Help / full keybinding list |
| `q` | Quit lazysql (kills the process -- prefer `<C-q>` to hide) |

Hitting `q` exits lazysql and drops the connection. Use `<C-q>` instead to tuck the float away while leaving the session alive.

## Codex in Neovim

`F5` (and the `<leader>A...` chords below) launches Codex through `bin/codex-nvim`, not raw `codex`. That wrapper does three things before Codex starts:

1. bootstraps the repo-local Codex bundle from `codex/` into `~/.codex`
2. prints a short welcome note in the terminal, including the `toggle-diff-editor on|off` reminder
3. starts Codex with a Neovim-specific startup prompt so the session already knows about the bundled `shell` and `toggle-diff-editor` skills

The bundled assets live in:

```text
codex/
  commands/
  skills/
  scripts/
```

This means someone cloning the public Neovim repo gets the Neovim-specific Codex skills from the repo itself instead of needing a second private skills repo.

### Safe vs trusted mode

Slot `5` is shared between the two modes, so only one can be running at a time:

- `F5` just toggles whatever is currently in slot `5`. If nothing is there yet it boots **safe** mode — that's the default.
- `<leader>As` / `:CodexSafe` force slot `5` into safe mode. Codex requires user approval for anything outside the sandbox.
- `<leader>At` / `:CodexTrusted` force slot `5` into trusted mode. The launcher adds `-a never -s danger-full-access`, which is what lets Neovim-RPC flows (`/skills/shell`, the live diff-editor review) run without prompting.

Switching between the two terminates the running terminal and opens a fresh one in the requested mode — you won't end up with two Codex terminals fighting over slot 5.

Add `!` to either command (`:CodexSafe!`, `:CodexTrusted!`) to skip session resume and start a new Codex session instead of picking up the last one.

### Bundled skills

- `shell`: sends a command into Neovim terminal slots `1` through `4`
- `toggle-diff-editor`: tells Codex to prefer or stop preferring the shared live patch-preview workflow

The launcher welcome message reminds users that `toggle-diff-editor on|off` exists so the feature is discoverable in a fresh Codex session.

## Floating Terminals on F-Keys

`F1` through `F4` each toggle their own floating shell, stacked with a slight cascade offset so you can eyeball which is which. Press the same key again from inside the terminal and it tucks away; press it again from anywhere and it's back, same shell, scrollback intact, any running process still going. That's `snacks.terminal.toggle` under the hood, keyed by slot number so each F-key gets its own persistent process.

```
F1 ──> Terminal 1 (78% of editor, top-left-ish)
F2 ──> Terminal 2 (cascaded slightly right+down)
F3 ──> Terminal 3 (cascaded more)
F4 ──> Terminal 4 (cascaded most)
F5 ──> Codex (toggle current slot-5 owner)
```

Keymaps work in both normal and terminal mode, so you can jump between the four without ever hitting `<C-\><C-n>`. Typical use: `F1` for `git`, `F2` for a running dev server, `F3` for ad-hoc `go test -run ...` loops, `F4` as a scratch REPL.

**Why four and not on-demand unlimited?** Fixed slots mean predictable muscle memory. The cascade offset also makes it visually clear when you've peeked at two terminals one after the other — they stack slightly rather than perfectly overlap.

**Scripting terminals from outside nvim.** The window layout and slot wiring now live in `lua/utils/term_send.lua` (a thin wrapper around `Snacks.terminal.toggle` / `.get`). It also exports `send(slot, cmd)`, which injects an arbitrary shell line into a slot's underlying job — useful when a sibling tool (a Claude skill, a shell script, a build wrapper) wants to kick off a long-running command in an already-visible terminal instead of backgrounding it or printing a copy-paste line.

Any subprocess of an nvim-managed terminal has `$NVIM` set to the parent's RPC socket, so the one-liner is:

```
nvim --server "$NVIM" --remote-expr 'v:lua.require("utils.term_send").send(1, "make test")'
```

`send` creates the slot if it doesn't exist, brings the window back if it was hidden, and appends a trailing newline so the command actually executes. The `/run` Claude skill uses this as a third "where to run it" option alongside background (nohup) and copy-paste — set the slot with `--term=<n>` or pick interactively.

## Markdown Preview

`<leader>mp` on any `*.md` buffer pops a floating [glow](https://github.com/charmbracelet/glow) render. `q` or `<Esc>` closes it. Requires the `glow` CLI (`sudo pacman -S glow` on Arch).

One subtle fix worth noting: glow.nvim pipes glow's stdout through a nvim terminal buffer rather than a real PTY, which makes `charmbracelet/termenv` strip ANSI styling by default — preview would show structural layout (headers, tables) but no colors. The config forces colors back on via `vim.env.CLICOLOR_FORCE = "1"` in the plugin's `init` hook. That's enough to get full syntax highlighting in code blocks, colored headers, inline-code backgrounds, italics — the works.

## The Stack

```
Neovim + LazyVim
├── Go (the language that says "no" so you don't have to)
├── TypeScript (the language that says "any" when you give up)
└── Claude (the AI that says "have you considered..." before saving your afternoon)
```

## License

[MIT](LICENSE) -- take what you want, blame no one.
