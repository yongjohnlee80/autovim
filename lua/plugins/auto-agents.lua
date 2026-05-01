-- auto-agents.nvim — multi-agent orchestration panel.
-- Slots 0-5 in the right window, slots 6-9 as snacks floats. Plus four
-- playground terminals T1..T4 mapped to F1..F4.
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
    version = "^0.1.0",  -- caret pins to v0.1.x; auto-updates within the line
    dependencies = {
      "folke/snacks.nvim",
      -- Soft dep: the diff-review bridge (per-agent `diff_review = true`).
      -- Without it, agents still run; opted-in agents fall back to the
      -- Claude Code TUI confirm prompt instead of the editor diff split.
      "coder/claudecode.nvim",
    },
    lazy = false,
    opts = opts,
    config = function(_, o)
      require("auto-agents").setup(o)
    end,
    keys = {
      { "<leader>a",  nil,                          desc = "AI / Auto Agents" },
      { "<leader>ac", "<cmd>AutoAgents<cr>",        desc = "Toggle auto-agents (last-focused slot)" },
      { "<leader>ap", "<cmd>AutoAgentsProject<cr>", desc = "Auto-agents project commands" },
      { "<F5>",       "<cmd>AutoAgents<cr>",        mode = { "n", "t" }, desc = "Toggle auto-agents panel" },
      { "<F6>",       "<cmd>AutoAgentsDock<cr>",    mode = { "n", "t" }, desc = "Auto-agents nav dock" },
      { "<F12>",      "<cmd>AutoAgentsDock<cr>",    mode = { "n", "t" }, desc = "Auto-agents nav dock" },
      -- Slot focus 0..9. Descriptions are static here (TOML drives the
      -- live agent list); call `:lua require('auto-agents').refresh_keymaps()`
      -- after wizard mutations to refresh which-key labels.
      { "<leader>a0", "<cmd>AutoAgentsFocus 0<cr>", desc = "Focus admin (slot 0)" },
      { "<leader>a1", "<cmd>AutoAgentsFocus 1<cr>", desc = "Focus slot 1" },
      { "<leader>a2", "<cmd>AutoAgentsFocus 2<cr>", desc = "Focus slot 2" },
      { "<leader>a3", "<cmd>AutoAgentsFocus 3<cr>", desc = "Focus slot 3" },
      { "<leader>a4", "<cmd>AutoAgentsFocus 4<cr>", desc = "Focus slot 4" },
      { "<leader>a5", "<cmd>AutoAgentsFocus 5<cr>", desc = "Focus slot 5" },
      { "<leader>a6", "<cmd>AutoAgentsFocus 6<cr>", desc = "Focus slot 6 (float)" },
      { "<leader>a7", "<cmd>AutoAgentsFocus 7<cr>", desc = "Focus slot 7 (float)" },
      { "<leader>a8", "<cmd>AutoAgentsFocus 8<cr>", desc = "Focus slot 8 (float)" },
      { "<leader>a9", "<cmd>AutoAgentsFocus 9<cr>", desc = "Focus slot 9 (float)" },
    },
  },
}
