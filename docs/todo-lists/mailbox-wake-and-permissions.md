# Mailbox wake + spawn-time permission injection

**Tags:** `type:todo-list` `living-doc` `owner:shared` `repo:auto-agents` `repo:auto-core` `area:mailbox` `area:permissions` `area:sandbox` `feature:agent-autonomy` `status:in-progress`

**Abstract:** auto-agents v0.2.7 wired the auto-core mailbox at spawn time, but the wake mechanism silently no-ops (no `send_slot` command is registered) and agents prompt for permission on every mailbox/KB file op. Both must land before agent-to-agent collaboration is actually autonomous.

- **Kickoff:** 2026-05-14
- **Owner(s):** shared (johno + jarvis + lector)
- **References:**
  - auto-agents `v0.2.7` (commit `020d4dd`) — mailbox spawn-time wiring
  - auto-core `v0.1.8` (commit `30a1298`) — per-instance isolation
  - `auto-core.nvim/main/lua/auto-core/mailbox/router.lua:204-212` — silent wake no-op
  - `auto-core.nvim/main/lua/auto-core/mailbox/commands.lua` — whitelisted command registry
  - `auto-agents.nvim/main/lua/auto-agents/init.lua:1136` — `M.send_slot(slot, text, opts)`
  - `auto-agents.nvim/main/lua/auto-agents/init.lua:1159` — `M.slot_for_name(name)`
  - `auto-core.nvim/main/lua/auto-core/mailbox/templates/bootstrap.md:43,86,106,136` — protocol references to `send_slot`, `send_user`, `harpoon`, `openDiff`

## Open

- [ ] **Register `harpoon` as a mailbox command.** Should live in md-harpoon.nvim (not auto-agents). Wire `require("auto-core").mailbox.commands.register("harpoon", ...)` from md-harpoon's setup; handler opens a markdown file into a preview slot. Skipped from v0.2.8 because the handler belongs to md-harpoon's namespace.

## In progress

_(empty)_

## Completed

- [x] **2026-05-14** — auto-core `v0.1.8` ships per-instance isolation API (`mailbox.register` auto-suffixes bare ids with `<unix-seconds>-<pid>`; `mailbox.env_for_agent(rec)`; per-tool-root bootstrap doc hoisting; `mailbox.prune` by age). Commit `30a1298`. Tag `v0.1.8`.
- [x] **2026-05-14** — auto-agents `v0.2.7` wires the auto-core mailbox at spawn time: per-instance mailbox registration in `build_agent_env`, central router started in `setup()`, four `AUTO_AGENTS_INSTANCE_ID`/`MAILBOX_ID`/`MAILBOX_DIR`/`MAILBOX_BOOTSTRAP_DOC` env vars injected. Commit `020d4dd`. Tag `v0.2.7`.
- [x] **2026-05-14** — auto-agents `v0.2.8` registers three mailbox commands with auto-core's whitelist: `wake` (canonical wake hook, renamed from internal `send_slot`), `addressbook` (live registry query — peers + `nvim` executioner + virtual `user`), `send_user` (vim.notify bridge). New `lua/auto-agents/mailbox/commands.lua` module; new project-level `MAILBOX.md` documenting protocol + command registry + dependencies + troubleshooting. Commit `f7d9696`. Tag `v0.2.8`.
- [x] **2026-05-14** — auto-core `v0.1.9` updates `mailbox/templates/bootstrap.md` so agents are instructed on `wake` + `addressbook` directly from the protocol doc. `schema_version` bumped 2 → 3; new "Discovering peers" section shows the addressbook query JSON shape. Doc revision auto-changes (sha256 of body), so agents will detect via `seen-revision` audit on next wake. Commit `9a72f76`. Tag `v0.1.9`.
- [x] **2026-05-14** — auto-agents `v0.2.9` ships spawn-time permission injection via a new `lua/auto-agents/permissions.lua` module. (Note: codex flag was wrong in v0.2.9 — see v0.2.10 fix below.) Commit `8f5116d`. Tag `v0.2.9`.
- [x] **2026-05-14** — auto-agents `v0.2.10` fixes the codex permission flag (`--add-dir`, not `--sandbox-workspace-write-root` — that was the TOML config field name, hallucinated by lector). Adds gemini support (`--include-directories <path>`). Adds the `diff_queue` mailbox command for non-Claude agents to enqueue diffs into the unified UI (fire-and-forget; Claude agents keep using the native ws openDiff MCP transport with blocking semantics). Commit `caa3fa5`. Tag `v0.2.10`.

## Blocked / deferred

_(empty — both open items are unblocked)_

## Notes

- The mailbox is functional for **human inspection** today: `ls $AUTO_AGENTS_MAILBOX_DIR/inbox/` works, and the router correctly routes outbox→inbox across cross-instance addressing (bare `to: "agent:jarvis"` resolves to the live full-id mailbox of the same instance). What's missing is the *autonomous* path — the wake nudge that gets the agent to act on inbound mail without a human prompting it.
- **Why send_slot belongs in auto-agents, not auto-core:** slots are an auto-agents abstraction (panel's `M.state.slot_terminals` mapping). auto-core's mailbox layer is deliberately generic — it owns the registry + dispatch shape, not the actions. The `commands.register` API is auto-core's hook for plugins to opt in.
- Pre-v0.2.7 bare-id mailbox trees (`~/.claude/mailbox/agent:jarvis/`, `~/.codex/mailbox/agent:lector/`) are inert legacy — `mailbox.prune` sweeps them by age after the 7-day default threshold.
- Both items together unblock the "agent restarts nvim → agents wake on inbox arrivals → process without human-in-the-loop permission prompts" flow that ADR 0013 is targeting.