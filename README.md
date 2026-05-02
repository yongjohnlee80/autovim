# AutoVim

An opinionated Neovim config built around AI pair programming (Claude Code + Codex), purpose-built for TypeScript and Go, with Omarchy / macOS / Ubuntu / Fedora variants maintained out of one repo.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/yongjohnlee80/autovim/main/install.sh | bash
```

The installer detects your OS (macOS, Arch, Debian / Ubuntu, Fedora), auto-picks the matching branch (macOS → `mac-os`, Arch + Omarchy → `omarchy`, everything else → `main`), installs baseline dependencies via your native package manager, backs up any existing `~/.config/nvim` to a timestamped `*.bak-…` directory, clones the repo, and runs a headless `Lazy sync` so your first launch is already warmed up.

Override the defaults with env vars:

```bash
AUTOVIM_BRANCH=main AUTOVIM_SKIP_DEPS=1 \
  curl -fsSL https://raw.githubusercontent.com/yongjohnlee80/autovim/main/install.sh | bash
```

`AUTOVIM_BRANCH` forces a specific branch, `AUTOVIM_REPO` installs from a fork, `AUTOVIM_SKIP_DEPS=1` skips the system-package step if you've already installed neovim (≥0.10), ripgrep, fd, fzf, git, gcc, and curl yourself.

## Why This Exists

Some people meditate. Some do yoga. I open Neovim, fire up Claude, and write Go and TypeScript until the world makes sense again. This is my happy place -- a terminal where keystrokes are cheap, feedback loops are tight, and the AI pair programmer never judges my variable names.

There's a certain poetry to it: Go for when you want the compiler to hold your hand, TypeScript for when you want the type system to argue with you, and Claude for when you want someone to tell you that your approach is "interesting" before gently suggesting you rewrite the whole thing. Neovim ties it all together like the world's most opinionated glue.

I've tried other setups. I've clicked through menus. I've dragged and dropped. I've used mice like some kind of animal. But nothing beats the flow of modal editing, instant AI assistance, and a config that loads faster than you can say "VS Code is updating." If the terminal is home, this config is the furniture.

## Multi-agent panel

[auto-agents.nvim](https://github.com/yongjohnlee80/auto-agents) replaces the single-agent claudecode panel with a **multi-slot orchestration window**. One right-side window hosts up to ten slots, plus four floating playground terminals. Every agent — Claude, Codex, Gemini, Copilot, or any shell — lives in its own slot with its own working directory, its own knowledge-base scope, and (optionally) its own diff-review behaviour.

### The slot model

```
                    ┌─────────────────────┐
       editor       │    auto-agents      │
                    │  ┌──────────────┐   │
                    │  │  winbar      │   │
                    │  │  0 1 2 3 4 5 │   │   slots 0–5: main panel
                    │  └──────────────┘   │   (one window, swapped buffers)
                    │  ░░░░░░░░░░░░░░░░   │
                    │  ░  agent term  ░   │
                    │  ░░░░░░░░░░░░░░░░   │
                    └─────────────────────┘

                   slots 6–9: snacks floats
                   T1..T4    : playground floats (F1..F4)
```

- **Slot 0 — admin REPL.** A prompt buffer with a tokenizing dispatcher, tab completion, and a help system. This is where wizards run (`agent add`, `kb init`, `project import`, …) and where you read `<verb> ?` docs in a scrollable popup.
- **Slots 1–5 — main panel.** Configured agents (Claude / Codex / Gemini / Copilot / generic) sharing one window. Empty slots fall back to `$SHELL`.
- **Slots 6–9 — sub-agent floats.** For ephemeral helpers, code-review passes, anything you want side-by-side rather than tabbed.
- **T1..T4 — playground terminals.** Shared shells for you and the agents; `term send <N> <text>` is paste-safe so an agent can dispatch a build into T2 without leaving its panel.

### Knowledge base (typed)

Every project's KB sits at one of two paths depending on where the agent's config came from:

- **Global agents** (defined in `<stdpath('config')>/.auto-agents-config/global.toml`) share **one** KB at `<stdpath('config')>/.auto-agents-config/kb`. Jarvis-everywhere reads the same conventions in every project.
- **Project agents** (defined in a per-project TOML) get a project-local KB at `<project>/.auto-agents/kb`.

Override either with `[kb].root = "/abs/path"` in the TOML. KBs are typed: pick **coding** (default for nvim users — codebase conventions, ADRs, review playbooks), **wiki** (Zettelkasten-flavored durable knowledge), **research** (papers / hypotheses / experiments), **ops** (alerts / runbooks / postmortems), **general** (minimal seed), or **custom** (you supply the seed `.md`). Each type ships an immutable `raw/` and a per-kind contract document (`AGENTS.md`, with `CLAUDE.md` and `GEMINI.md` pointers) that the agent auto-loads at spawn. `kb ingest` produces a deterministic worklist of new / edited / current / orphan raw files; `--attach <N>` pipes the worklist to slot N.

### Navigation flow

A typical session opens `:AutoAgents` (or `<F5>`) and lands on the admin slot. From there:

- **Direct slot focus.** `<leader>a0`..`a9` jumps to that slot. Inside admin, the same digits work in normal mode (no leader needed).
- **Navigation dock.** `<F6>` (or `<F12>`) opens a small right-edge float listing every slot plus the editor. Press a digit to jump, `e` to return to the editor, anything else to dismiss. Mode-safe — terminal mode doesn't leak into editor buffers.
- **Help on demand.** `<verb> ?` (e.g. `agent add ?`, `kb init ?`) pops a scrollable floating help window. `help open <verb>` opens the underlying markdown if you want to edit it.
- **Wizards.** `agent add`, `agent edit`, `kb init`, `project init` walk you through prompts inside the admin REPL. `<C-c>` aborts at any step. Default for `kind = "claude"`: `diff_review = true` so that agent's edits open as a diff split in your editor; sub-agents default to `false` so their edits stay in their own terminals.

### Diff-review bridge

`diff_review = true` per agent (set during the `agent add` wizard) makes that agent's proposed edits open as a diff split in your editor — left current, right proposed. **You can edit the proposed side manually** before accepting. `:w` accepts, closing the diff rejects. Implemented by injecting `CLAUDE_CODE_SSE_PORT` into the agent's spawn so Claude Code CLI's `openDiff` MCP tool routes through claudecode.nvim. Agents with `diff_review = false` use Claude Code's TUI confirm prompt in their own terminal — useful for sub-agents whose edits you don't want popping at you alongside your main coding agent's.

## What's Inside

- **[LazyVim](https://www.lazyvim.org/)** -- because life's too short to configure everything from scratch, but too long to use someone else's config without tweaking it
- **[auto-agents.nvim](https://github.com/yongjohnlee80/auto-agents)** -- another plugin I wrote: multi-agent orchestration panel. One right-side window holds up to ten slots — slot **0** is an admin REPL with a step-by-step wizard, slots **1–5** are main-window agent terminals, slots **6–9** open as floats. Plus four playground terminals **T1..T4** mapped to F1..F4. Specialized **knowledge-base** per project (typed: coding / wiki / research / ops / general / custom) with an immutable `raw/` and shared/private/isolated scopes. TOML-driven config under `<stdpath('config')>/.auto-agents-config/` survives `:cd`. `<F5>` toggles the panel; the admin's wizard creates agents, projects, and KBs by walking you through prompts. See [Multi-agent panel](#multi-agent-panel) below
- **[claudecode.nvim](https://github.com/coder/claudecode.nvim)** -- soft dependency that auto-agents leans on for the **diff-review bridge**. Per-agent `diff_review = true` in the TOML routes that agent's proposed edits to a diff split in the editor (left current, right proposed; edit the right side, `:w` accepts, close rejects)
- **LSP + Mason** -- language servers managed properly, so Go and TypeScript just work
- **Treesitter** -- syntax highlighting that understands your code, not just your brackets
- **[nvim-dap](https://github.com/mfussenegger/nvim-dap) + [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view) + [nvim-dap-go](https://github.com/leoluz/nvim-dap-go)** -- delve-powered Go debugging with a minimalist inspection panel. Breakpoints, step controls, watches, attach-to-process, and debug-test-under-cursor
- **[worktree.nvim](https://github.com/yongjohnlee80/worktree.nvim)** -- in-editor worktree switcher I wrote. Hops between repos/worktrees under the directory you opened nvim in, with safety rails on add/remove and ghost-buffer cleanup. Comes with a lualine component and optional LSP re-anchor on switch
- **[gobugger.nvim](https://github.com/yongjohnlee80/gobugger.nvim)** -- another plugin I wrote. Opinionated Go debugger: launch.json-driven, worktree-aware, delve-integrated, dap-view as the UI. Picker with session cache, scaffolder for new test/main entries, doctor command for diagnosing build/worktree issues
- **[lazysql](https://github.com/jorgerojas26/lazysql)** -- a TUI SQL client hoisted into a floating window via `snacks.terminal`. Pre-configured connections, one keystroke to toggle, and the process stays alive between toggles so you don't pay the connection cost twice
- **[kulala.nvim](https://github.com/mistweaverco/kulala.nvim)** -- HTTP client driven by `.http` files. Replaced `rest.nvim` (whose luarocks build chain was miserable on macOS). Per-project scaffold under `.rest/` via `<leader>Rs`, a single gitignored `http-client.private.env.json` with generic keys (`BASE_URL`, `USER_NAME`, `USER_PASS`, `API_KEY`), and `<leader>Rr` / `<leader>Rl` / `<leader>Ra` to run / replay / run-all
- **[md-render.nvim](https://github.com/delphinus/md-render.nvim)** -- terminal-native Markdown previewer with rich layout: tables with box-drawing borders, callouts with icons + colored bars, fenced code blocks with treesitter syntax highlighting, OSC 8 hyperlinks, and inline images / video / Mermaid diagrams via the Kitty graphics protocol. The plugin's bundled preview is a single float; we layer [`yongjohnlee80/md-harpoon.nvim`](https://github.com/yongjohnlee80/md-harpoon.nvim) on top so `<leader>m{q,w,e,a,s,d}` host six coexisting floats arranged in a 2×3 grid — top row q/w/e, bottom row a/s/d — with per-slot cursor memory and a fuzzy file picker on `<leader>mf`. Replaces `glow.nvim`
- **Floating playground terminals** — four toggleable floats on `F1`–`F4`, owned by [auto-agents.nvim](https://github.com/yongjohnlee80/auto-agents) (the `T1..T4` slots in the [Multi-agent panel](#multi-agent-panel) section). Each has its own persistent shell, marker-based lookup that survives `:cd`, and works from normal *and* terminal mode. `:AutoAgentsTermSend <slot> <text>` (paste-safe) lets agents drive them programmatically
- **Remote sync** ([`yongjohnlee80/remote-sync.nvim`](https://github.com/yongjohnlee80/remote-sync.nvim)) -- a local-first / git-backed workflow for editing files on a shared remote without ever logging Claude or Codex into that remote. Drop a `.autovim-remote.json` at the root of a local mirror; `<leader>rp` / `<leader>rd` / `<leader>rs` / `<leader>rS` / `<leader>rc` / `<leader>rl` drive pull / drift-check / push / force-push / configured remote command / log float. Drift detection compares **remote vs git HEAD** (not working tree), so unpushed local edits don't trigger spurious drift. See [Remote Development](#remote-development) for the workflow
- **11 colorschemes** -- because choosing a theme is a form of self-expression (currently rotating through them like outfits)

## Dependencies

One external binary this config relies on that doesn't install itself through Lazy or Mason:

- **`lazysql`** — the TUI SQL client wired to `<C-q>`. The Neovim side is just a `snacks.terminal` toggle; the binary has to be on your `$PATH`.

| Tool | Arch | macOS |
|---|---|---|
| `lazysql` | `yay -S lazysql-bin` (AUR) | `go install github.com/jorgerojas26/lazysql@latest` |

Connection setup for `lazysql` lives in [SQL Without Leaving Neovim](#sql-without-leaving-neovim).

## Key Bindings Worth Knowing

### Editing & AI agents (auto-agents.nvim)

| Binding | What It Does |
|---|---|
| `jk` | Escape insert mode (the only correct mapping) |
| `<F5>` | Toggle the auto-agents panel (last-focused slot) |
| `<F6>` / `<F12>` | Open the navigation dock (one-key slot dispatch) |
| `<leader>ac` | Toggle the panel |
| `<leader>ap` | `:AutoAgentsProject` — init/import/remove/list/show |
| `<leader>a0` | Focus admin (slot 0) — the REPL where wizards live |
| `<leader>a1`..`a9` | Focus slot N — 1..5 in the main panel, 6..9 as floats |

Inside the panel:

- The admin REPL has a step-by-step wizard for `agent add`, `agent edit`, `kb init`, `kb scope`, `project init`, `project import`. Every step shows `[current]`; press Enter to keep, type to change, **`<C-c>` to cancel**.
- `<verb> ?` (or `<verb> <sub> ?`) opens a scrollable floating help window. `help open <verb>` opens the underlying markdown for hand-editing.

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

### Playground terminals (T1..T4)

Auto-agents brings four shared floating shells — separate from agent slots — keyed to F1..F4. Same key:

| State                          | Effect            |
|--------------------------------|-------------------|
| Slot N has no terminal yet     | Create + focus    |
| Slot N hidden                  | Show + focus      |
| Slot N visible, unfocused      | Move focus to it  |
| Slot N visible, focused        | Hide              |

Moving focus into any non-float window auto-hides every T1..T4 float at once (scoped — won't fight lazygit / lazysql). The T-floats persist across `:cd` (marker-based lookup bypasses snacks's cwd hashing), so an interactive REPL stays alive when you hop worktrees.

Plus `:AutoAgentsTermSend <slot> <text>` (paste-safe via a 60ms-deferred CR) lets agents drive the playground programmatically.

| Binding | What It Does |
|---|---|
| `F1`..`F4` | Auto-agents playground terminal T1..T4 (focus / hide) |
| `F5` | Toggle the auto-agents panel |
| `F6` / `F12` | Open the auto-agents navigation dock |

### Markdown

| Binding | What It Does |
|---|---|
| `<leader>ma` / `<leader>ms` / `<leader>md` | Slot left / middle / right — focus if open, reopen with last doc, or render the current buffer (smart fallback for first use) |
| `<leader>mA` / `<leader>mS` / `<leader>mD` | Render the current buffer into slot left / middle / right (replaces what was there) |
| `<leader>mt` | Tab preview (full-screen) |
| `q` / `<Esc>` / `<CR>` (inside a float) | Close that float |

### Remote development (sync-based)

| Binding | What It Does |
|---|---|
| `<leader>rp` | Pull remote → local mirror (rsync); auto-`git commit` the result as a snapshot. HEAD becomes "current remote state" — the baseline for the next drift comparison |
| `<leader>rd` | Drift report — compares remote against `git HEAD` (NOT working tree). So unpushed local edits never count as drift; only *the remote* changing since your last sync does |
| `<leader>rs` | Push local → remote: drift-check (refuses if remote drifted), commit working tree as `snap pre-push`, rsync push, quiet auto-pull. The pre-push commit means HEAD always reflects what was last sent — keeps drift detection honest across sessions |
| `<leader>rS` | **Force push** — bypasses the drift gate. `vim.ui.select` confirms first because the gate exists for a reason (prevents silently overwriting remote changes) |
| `<leader>rc` | Run a project-configured remote command over ssh. Reads `commands: [{name, cmd}, ...]` from the JSON; multi-entry → picker, single entry → runs directly |
| `<leader>rl` | Show the last sync's full output in a floating window |
| `<leader>rR` | Register a new project — wizard prompts for host / remote_path / dest_path (default: `cwd/<last-two-of-remote-path joined by ->` lowercased), creates the dir and writes a default `.autovim-remote.json` |
| `<leader>gq` | Pick a remote project (any `.autovim-remote.json` under `~/Source/Remote/` or fallbacks) and `:cd` to it. Pushes the previous cwd onto an in-memory stack |
| `<leader>gQ` | `:cd` back to where you were before the last `<leader>gq` (LIFO; mirrors worktree.nvim's `<leader>gw` / `<leader>gW` pattern within our own keyspace) |

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

## Floating Terminals on F-Keys

`F1` through `F4` toggle four playground terminals owned by [auto-agents.nvim](https://github.com/yongjohnlee80/auto-agents) (the `T1..T4` slots described in [Multi-agent panel](#multi-agent-panel)). Each is a persistent floating shell — same key from inside hides it, same key from outside brings it back, marker-based lookup that survives `:cd`. F5 is the panel toggle, not a fifth terminal — Codex / Claude / Gemini / etc. live as agent slots **inside** the panel now (configure via `agent add` in the admin REPL).

```
F1 ──> Playground T1
F2 ──> Playground T2
F3 ──> Playground T3
F4 ──> Playground T4
F5 ──> Auto-agents panel toggle
```

**Scripting terminals from outside nvim.** The plugin exposes `require("auto-agents.term").send(slot, cmd)` which injects an arbitrary shell line into a playground terminal's underlying job — useful when a sibling tool (a Claude skill, a shell script, a build wrapper) wants to kick off a long-running command in an already-visible terminal instead of backgrounding it or printing a copy-paste line. The `:TermSend <slot> <cmd>` and `:AutoAgentsTermSend <slot> <text>` user commands wrap the same call.

Any subprocess of an nvim-managed terminal has `$NVIM` set to the parent's RPC socket, so the one-liner is:

```
nvim --server "$NVIM" --remote-expr 'v:lua.require("auto-agents.term").send(1, "make test")'
```

`send` creates the slot if it doesn't exist, brings the window back if it was hidden, and the paste-safe submit (deferred CR) means TUIs read the payload as a paste followed by a single Enter keystroke. The `/run` Claude skill uses this as a third "where to run it" option alongside background (nohup) and copy-paste — set the slot with `--term=<n>` or pick interactively.

## Markdown Preview

[md-render.nvim](https://github.com/delphinus/md-render.nvim) renders Markdown into a separate floating / tab / pager window — your editing buffer stays untouched (cf. `render-markdown.nvim`, which mutates the buffer in place). Tables get box-drawing borders, callouts get icons + colored bars, fenced code blocks pick up treesitter syntax highlighting, OSC 8 hyperlinks are clickable in compatible terminals, and inline images / video / Mermaid diagrams render via the Kitty graphics protocol.

### Six slots for side-by-side comparison

The plugin's `MdPreview.show()` keeps a single module-level FloatWin and `close_if_valid`s it on every call, so calling it multiple times can't yield multiple coexisting floats. The slot manager lives in [`yongjohnlee80/md-harpoon.nvim`](https://github.com/yongjohnlee80/md-harpoon.nvim), which wraps md-render's library API (`FloatWin` / `display_utils` / `preview.build_content` — exposed for embedding per its "Usage as a library" section) into six per-slot floats laid out in a 2×3 grid:

```text
<leader>mq <leader>mw <leader>me   ┐
<leader>ma <leader>ms <leader>md   ├── lowercase: smart "open / focus" — restores cursor
                                   ┘

<leader>mQ <leader>mW <leader>mE   ┐
<leader>mA <leader>mS <leader>mD   ├── uppercase: explicit re-render → cursor at top
                                   ┘

<leader>mf ──> Fuzzy-find a markdown file → pick a panel
<leader>mt ──> Full-screen tab preview
```

The lowercase keys collapse three behaviors into one keystroke:

1. Float open in that slot → jump cursor into it
2. Float closed but slot has a remembered source → reopen it with the cursor restored to where you left it (you dismissed it earlier with `q`)
3. Slot never used → render the current buffer (so first use just works)

Uppercase keys always render the current buffer into the slot, cursor at line 1 — explicitly "load a fresh document here". `<leader>mf` opens a fuzzy file picker over `*.md` under cwd (Snacks.picker when available) and prompts for a panel after selection — useful when you want a doc that isn't already in a buffer. Together this lets you compare up to six documents at once.

Press `q` / `<Esc>` / `<CR>` inside any float to dismiss it (plugin default). Bring it back later with the lowercase key — your cursor position is preserved.

### Terminal compatibility

| Terminal | Status |
|---|---|
| Ghostty / Kitty / WezTerm | Fully verified by upstream — text + images + video + Mermaid all work |
| iTerm2 | Not in upstream's verified list. Text rendering (tables, callouts, code blocks, OSC 8 links) works anywhere. iTerm2 3.5+ has partial Kitty graphics support, but the plugin author hasn't validated it — images / video / Mermaid are "your mileage may vary" until that's confirmed |

### Optional dependencies

Text rendering needs nothing beyond Neovim. The rich-media features pull in a few external tools — install only what you actually need:

| Tool | Purpose | Install |
|---|---|---|
| `ffmpeg` | JPEG/WebP → PNG conversion, video frame extraction | `pacman -S ffmpeg` / `brew install ffmpeg` |
| ImageMagick (`magick`) | Same conversions; ffmpeg fallback | `pacman -S imagemagick` / `brew install imagemagick` |
| Mermaid CLI (`mmdc`) | Render Mermaid blocks (falls back to slow `npx -y` if absent) | `npm install -g @mermaid-js/mermaid-cli` |

## Remote Development

A local-first / git-backed sync workflow for editing files on a shared remote *without* logging Claude or Codex into that remote. Nvim runs locally with full AI/LSP, files travel via rsync into a persistent local mirror, and git on the local mirror handles snapshot / drift / merge.

The full architecture and rationale are in [`docs/design-decisions/2026-04-25-remote-dev-local-first-git-backed-sync.md`](docs/design-decisions/2026-04-25-remote-dev-local-first-git-backed-sync.md).

### Setup per project

Drop a `.autovim-remote.json` at the root of the local mirror dir:

```json
{
  "host": "user@vps.team",
  "remote_path": "/srv/mailcow/data/conf",
  "exclude": [".git", "data", "logs", "node_modules"],
  "delete": true,
  "detection": "safe",
  "commands": [
    { "name": "restart", "cmd": "cd /srv/mailcow && docker compose restart postfix-mailcow" }
  ]
}
```

| Field | Required | What it does |
|---|---|---|
| `host` | yes | ssh destination (`user@host` or an alias from `~/.ssh/config`) |
| `remote_path` | yes | Remote directory the local mirror tracks |
| `exclude` | no | rsync `--exclude` list. Defaults exclude local metadata (`.git`, `.autovim-remote.json`, `.env`), build artifacts (`node_modules`, `vendor`, `.direnv`, `target`), OS noise (`.DS_Store`), and cert/key material (`*.pem`, `*.key`, `*.crt`, `*.cert`, `*.p12`, `*.pfx`, plus the `ssl` directory itself — covers the case where mode-700 cert dirs would error rsync's recursive scan). Override per project to expand or replace |
| `delete` | no | Whether `<leader>rs` passes `--delete-after` (clean mirror). Default `false` (additive push) |
| `detection` | no | One of `"lazy"` / `"safe"` / `"paranoid"` — controls how rsync decides what's changed (per-operation flag bundle). Default `"safe"`. See [Detection modes — fast push, safe pull](#detection-modes--fast-push-safe-pull) below |
| `commands` | no | Array of `{name, cmd}` entries for `<leader>rc`. Multi-entry → picker; single entry → runs directly. See snippet below |

`commands` example for a service that benefits from more than just "restart":

```json
"commands": [
  { "name": "restart",     "cmd": "cd /home/admin/Docker/forgejo && docker compose restart forgejo" },
  { "name": "stop",        "cmd": "cd /home/admin/Docker/forgejo && docker compose stop" },
  { "name": "logs",        "cmd": "cd /home/admin/Docker/forgejo && docker compose logs --tail=200 forgejo" },
  { "name": "renew-cert",  "cmd": "certbot renew && nginx -t && systemctl reload nginx" }
]
```

Add `.autovim-remote.json` to your local mirror's `.gitignore` if there's anything host-specific in it. Without the file, every `<leader>r*` keymap notifies and no-ops — safe to mash anywhere.

### Recommended workflow (per session)

```
<leader>rp         pull + auto-snapshot (HEAD = "current remote state")
… edit files locally, no need to git commit between edits …
<leader>rd         drift check (HEAD vs remote — local edits don't count)
<leader>rs         push: drift check, auto-snap pre-push, rsync, auto-pull post-push
<leader>rS         FORCE push (confirm prompt; bypasses drift gate)
<leader>rc         (optional) reload the service on the remote
```

The local mirror is **persistent** — keep the directory and its `.git` around between sessions. Each successful sync (pull or push) advances `HEAD` so it always represents "last synced state in either direction." Deleting `.git/` forfeits drift detection and history.

### How drift detection actually works (the 3-way reference)

Drift is "did the remote change since our last sync?" — NOT "do local files differ from remote files?" The distinction matters because *of course* local files differ from remote when you've been editing them; that's the whole point of the workflow. The drift gate exists to detect a different failure mode: someone else (or some automated process) modified the remote while you were editing locally, and pushing now would silently overwrite their changes.

Three references:

| Reference | What it represents |
|---|---|
| **`git HEAD`** | Last synced state in either direction (auto-snapped after every successful pull or pre-push) |
| **Working tree** | Current local state, including uncommitted edits |
| **Remote** | What's on the VPS right now |

`<leader>rd` and `<leader>rs`'s drift check compare **remote vs HEAD**, NOT remote vs working tree. So:

- ✅ Local has unpushed edits, remote unchanged → drift check is clean → push proceeds
- ❌ Remote has changes since last pull, local unchanged → drift detected → push refused, pull-merge required
- ❌ Both edited concurrently → drift detected → conflict, manual resolve via git

`<leader>rs` also commits a `pre-push` snap before the rsync, so `HEAD` always tracks what was last sent. That's how the model stays coherent across editing sessions: every successful push leaves `HEAD == remote`, and the next drift check uses that as its baseline.

If you genuinely need to push past a drift warning (e.g., you know the remote change is something you want to overwrite — perhaps a leftover state from a prior misconfiguration), use `<leader>rS` (capital). It prompts via `vim.ui.select` to confirm; the friction is intentional.

The first `<leader>rp` auto-bootstraps a git repo in the local mirror dir (if it isn't already one) and commits the pulled state as the initial snapshot. **The `.autovim-remote.json` is tracked in git on purpose** — it contains no credentials (just host + path + commands), and tracking it means cloning the mirror onto a new laptop instantly restores the workflow with no manual reconstruction. The rsync side still excludes it via the per-project `exclude` list, so the VPS never sees it. Users who want it gitignored anyway can add `.autovim-remote.json` to `.gitignore` by hand. If the mirror dir happens to be *inside* an ancestor git repo (e.g. accidentally dropped under an existing project tree), the snapshot commit is skipped with a warning — `git_state` walks up via `git rev-parse --show-toplevel` to detect this and avoid polluting the parent repo's history.

To bootstrap a new project without typing the JSON by hand: `<leader>rR` opens a three-prompt wizard for host / remote_path / dest_path. The dest_path default is `cwd/<last-two-of-remote-path joined by ->` lowercased — e.g. `/home/admin/Docker/test` → `cwd/docker-test`, `/srv/mailcow/data/conf` → `cwd/data-conf`. The wizard creates the dir and writes a default `.autovim-remote.json`; you `:cd` in and run `<leader>rp` afterward.

### Detection modes — fast push, safe pull

The `detection` field in `.autovim-remote.json` picks how rsync decides what counts as a change. Three named modes; default is `"safe"`.

#### Philosophy

The three operations have asymmetric risk profiles, and the right detection algorithm differs by operation:

- **Push is intentional.** You just edited something. You *want* the bumped mtime to signal "send this." If push detects too much (false positive), you wasted a few KB of bandwidth — recoverable. Push is fast and re-runnable.
- **Pull is destructive on conflict.** If rsync's stat-based view says "remote file differs" because some container bumped a file's mtime, pull would silently overwrite your unpushed local edits. The cost of a false positive on pull is **lost work** — by far the most expensive failure mode in the workflow.
- **Drift is the gate.** `<leader>rs` runs a drift check first and refuses to push on any divergence. False positives here block legitimate pushes (forcing pull-then-push or `force=true`); false negatives let you push over a remote update you didn't see.

So push wants speed; pull wants safety; drift wants accuracy. The default mode (`safe`) reflects this: stat-based for push, content-based (`--checksum`) for pull and drift. You can override per-project for either extreme — `lazy` if performance matters more than safety, `paranoid` if you've seen size+mtime equality lie about content.

#### The three modes

| Mode | Push | Pull | Drift | When to use |
|---|---|---|---|---|
| **`lazy`** | stat | stat | stat | All operations trust rsync's default size+mtime detection. Fastest. Vulnerable to phantom mtime drift bumping the gate or silently overwriting on pull. Use when no service is actively writing into the mirror tree (static config snapshots, test fixtures, etc.) |
| **`safe`** *(default)* | stat | **checksum** | **checksum** | Push trusts your intent (fast); pull and drift compare content. The right default for active service mirrors where containers constantly bump dir mtimes |
| **`paranoid`** | checksum | checksum | checksum | Content-compare everywhere, including push. Slowest. Use when size+mtime equality has been observed to lie about content (rare; e.g., generators rewriting files in place with identical metadata) |

#### What each mode actually fixes

The two real-world failure modes the design was built around, and which mode prevents which:

| Mode | Phantom dir-mtime drift blocks `<leader>rs`? | Phantom file-mtime drift can silently overwrite local edits on `<leader>rp`? | "Same size+mtime but different content" can be missed? |
|---|---|---|---|
| `lazy` | ✗ Fixed (via universal `-O`) | ⚠️ Risk remains | ⚠️ Risk remains |
| `safe` *(default)* | ✗ Fixed | ✗ Fixed (`--checksum` on pull) | ⚠️ Risk remains on push only (rare) |
| `paranoid` | ✗ Fixed | ✗ Fixed | ✗ Fixed (`--checksum` on push too) |

The dir-mtime fix is mode-independent — `-O` is applied universally, so even `lazy` no longer reports `.d..t...... ./` in drift output. Mode choice is really about *file*-level safety on pull, not the dir-level noise.

#### Universal flags (all modes)

Two flag bundles are correct in *every* mode and not exposed as configuration:

- **`-O` (`--omit-dir-times`)** — kills phantom drift from container-bumped parent-directory mtimes (the symptom that motivated this whole design). Directory mtimes are a side effect of file writes, not an intentional signal.
- **`--no-owner --no-group`** — cross-user pushes can't preserve UID/GID anyway; preserving produces noise + exit-23 warnings.

#### Mental model

> **`lazy` says "I trust the mtimes."**
> **`safe` says "I trust the mtimes locally; I don't trust what the remote did between syncs."**
> **`paranoid` says "I trust nothing; check every byte."**

Most active service mirrors should be `safe`. Most snapshot mirrors (cold storage, test fixtures) can be `lazy`. Almost no one needs `paranoid`.

The full design rationale lives in [`docs/design-decisions/2026-04-26-rsync-detection-modes.md`](docs/design-decisions/2026-04-26-rsync-detection-modes.md).

### When *not* to use this

- For source code on a self-hosted git host, use normal `git push` / `git pull` — rsync is a transport, not a version-control system.
- For huge data dirs (databases, caches, mail spools): rsync round-trips will be slow and the local mirror will balloon. The pattern is intended for service config trees and small source dirs.
- For **disaster recovery**: the local git mirror covers configuration, not application data, secrets, or DB state. It is *not* a backup. Plan DR independently (restic/borg to off-site, scheduled DB dumps, per-service runbooks, tested restores).

## The Stack

```
Neovim + LazyVim
├── Go (the language that says "no" so you don't have to)
├── TypeScript (the language that says "any" when you give up)
└── Claude (the AI that says "have you considered..." before saving your afternoon)
```

## License

[MIT](LICENSE) -- take what you want, blame no one.
