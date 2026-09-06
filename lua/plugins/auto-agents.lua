-- auto-agents.nvim — multi-agent orchestration panel.
-- Slot 0 is the admin REPL; slots 1..N are flat right-panel agent
-- workspaces (N = the live `panel.slot_count`, configurable via the
-- admin verb `slot add` / `slot remove`). Unconfigured slots fall
-- back to a shell — usable as a terminal workspace, not an empty
-- placeholder. Plus four playground terminals T1..T4 mapped to F1..F4.
--
-- Plugin source: remote release.
--
-- Agents/KB are not configured here — the TOML store at
-- `<stdpath('config')>/.auto-agents-config/<project-key>.toml` (per-project)
-- with fallback to `global.toml` is the source of truth. Open the panel
-- (`:AutoAgents` / `<F5>`) and use the admin slot's wizard (`agent add`,
-- `project init`, etc.) to populate it.
local opts = {
  log_level = "info",
}

return {
  {
    "yongjohnlee80/auto-agents",
    version = "^0.2.0",
    dependencies = {
      "folke/snacks.nvim",
      -- Soft dep: the diff-review bridge (per-agent `diff_review = true`).
      -- Without it, agents still run; opted-in agents fall back to the
      -- Claude Code TUI confirm prompt instead of the editor diff split.
      "coder/claudecode.nvim",
      -- auto-core foundation — referenced by name; spec lives in
      -- lua/plugins/auto-core.lua. Hard dep as of v0.2.0.
      "auto-core.nvim",
    },
    lazy = false,
    opts = opts,
    config = function(_, o)
      require("auto-agents").setup(o)
    end,
    keys = {
      -- The group prefix, declared for BOTH modes it has bindings in.
      -- lazy.nvim defaults `mode` to normal, so a bare entry left the prefix
      -- with no scaffolding in visual mode — and `<leader>af` is the one entry
      -- under it that binds visual. which-key then had no group to show there,
      -- so the prefix read as unmapped even though `af` was live behind it
      -- (Johno, 2026-09-07).
      { "<leader>a", nil, mode = { "n", "x" }, desc = "AI / Auto Agents" },
      { "<leader>ac", "<cmd>AutoAgents<cr>", desc = "Toggle auto-agents (last-focused slot)" },
      { "<leader>ad", "<cmd>AutoAgentsDiffQueue<cr>", desc = "Toggle unified diff queue" },
      { "<F11>", "<cmd>AutoAgentsDiffQueue<cr>", mode = { "n", "t" }, desc = "Toggle unified diff queue" },
      -- ADR 0024 / ADR-0036: operator-side bootstrap-refresh recovery
      -- keymaps. Slot picker → deterministic prompt → paste-safe submit.
      -- Plugin owns the prompt body so behaviour stays deterministic
      -- across invocations. (`<leader>ap` was repurposed from the old
      -- `:AutoAgentsProject` shortcut — that command is still callable
      -- directly via `:AutoAgentsProject`.)
      {
        "<leader>am",
        function() require("auto-agents").reingest_bootstrap_picker() end,
        desc = "Re-ingest bootstrap doc into a slot",
      },
      {
        "<leader>ai",
        function() require("auto-agents").reassert_identity_picker() end,
        desc = "Re-assert runtime identity for a slot",
      },
      {
        "<leader>ap",
        function() require("auto-agents").permission_bootstrap_picker() end,
        desc = "Bootstrap mailbox permissions for a slot (PERMISSION.md)",
      },
      -- ADR-0045: send the current editor buffer to a live agent slot.
      -- Buffer captured at invocation → slot picker → "Instructions:"
      -- input → file-path reference pushed via send_slot. Plugin
      -- function ships in auto-agents v0.2.58+ (within `^0.2.0`).
      {
        "<leader>ab",
        function() require("auto-agents").send_buffer_picker() end,
        desc = "Send current buffer to an agent",
      },
      -- ADR-0082: forward selected text (visual mode) or clipboard (normal mode)
      -- to a live agent slot with snippet confirmation prompt and mailbox delivery.
      {
        "<leader>af",
        function() require("auto-agents").forward_text_picker() end,
        mode = { "n", "x" },
        desc = "Forward selected text / clipboard to an agent",
      },
      { "<F5>", "<cmd>AutoAgents<cr>", mode = { "n", "t" }, desc = "Toggle auto-agents panel" },
      -- `<F6>` is NOT here any more: it now opens the central navigation modal,
      -- bound in `lua/config/keymaps.lua` beside `<C-g>`. The dock reached only
      -- auto-agents' own slots; the modal reaches those AND the finder
      -- sections, terminals, buffers and views — and it is the surface the
      -- rest of v0.4 is built around, so the second F-key that used to
      -- duplicate the dock is better spent on it. `<F12>` keeps the dock for
      -- anyone who still wants the narrow, agents-only list.
      --
      -- It is bound over THERE rather than here because the modal is config,
      -- not part of this plugin: leaving it in this spec would make `<F6>`
      -- disappear the moment someone disables auto-agents, and would route the
      -- keypress through lazy's loader for a plugin the modal never calls.
      { "<F12>", "<cmd>AutoAgentsDock<cr>", mode = { "n", "t" }, desc = "Auto-agents nav dock" },
      -- Slot focus keymaps (`<leader>a0..aN`) are NOT registered here.
      -- The plugin owns them: `auto-agents.setup()` calls
      -- `refresh_keymaps()` which registers `<leader>a0..aMAX_SLOT`
      -- with live `slot_desc(N)` descriptions (agent title for
      -- configured slots, "shell" for the unconfigured trailing
      -- slot). The same callback fires from `state.watch_slot_count`,
      -- so growing/shrinking `slot_count` via `slot add N` /
      -- `slot remove N` reflects in which-key immediately — no
      -- restart, no consumer-config edit. Plugin v0.2.15+.
    },
  },
}
