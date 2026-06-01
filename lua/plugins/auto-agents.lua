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
      { "<leader>a", nil, desc = "AI / Auto Agents" },
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
      { "<F5>", "<cmd>AutoAgents<cr>", mode = { "n", "t" }, desc = "Toggle auto-agents panel" },
      { "<F6>", "<cmd>AutoAgentsDock<cr>", mode = { "n", "t" }, desc = "Auto-agents nav dock" },
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
