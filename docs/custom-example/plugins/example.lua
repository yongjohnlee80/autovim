-- Example custom plugin spec.
--
-- Every file under `lua/custom/plugins/` must return a lazy.nvim spec
-- (a table) or a list of specs. lazy.nvim imports them AFTER the stock
-- AutoVim specs in `lua/plugins/`, and merges specs that share the
-- same repo name — so this is the place to:
--
--   1. Install brand-new plugins.
--   2. Tweak opts / keys / dependencies of stock plugins.
--   3. Disable stock plugins.
--
-- Delete this file once you've added your own.

return {
  --
  -- 1. Install a brand-new plugin
  --
  -- {
  --   "folke/zen-mode.nvim",
  --   cmd = "ZenMode",
  --   keys = { { "<leader>z", "<cmd>ZenMode<cr>", desc = "Zen mode" } },
  --   opts = {},
  -- },

  --
  -- 2. Override a stock plugin's opts (merges by repo name)
  --
  -- {
  --   "yongjohnlee80/auto-agents",
  --   opts = function(_, opts)
  --     opts.panel = vim.tbl_extend("force", opts.panel or {}, {
  --       slot_count = 8,
  --     })
  --     return opts
  --   end,
  -- },

  --
  -- 3. Disable a stock plugin entirely
  --
  -- { "yongjohnlee80/gobugger", enabled = false },

  --
  -- 4. Replace a stock plugin's lazy-load keys
  --
  -- {
  --   "yongjohnlee80/worktree.nvim",
  --   keys = {
  --     { "<leader>gw", false },                              -- drop stock
  --     { "<leader>W",  function() require("worktree").pick() end, desc = "Worktree pick" },
  --   },
  -- },
}
