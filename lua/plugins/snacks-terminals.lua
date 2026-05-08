-- F1..F4 are now owned by auto-agents.nvim (see lua/plugins/auto-agents.lua
-- and the plugin's `lua/auto-agents/term/` modules). Same focus-or-hide
-- behavior, marker-based lookup that survives `:cd`, scoped auto-hide on
-- editor focus. This file just keeps the snacks terminal style override
-- so any *other* snacks terminals (lazygit, lazysql, plugin/codex.lua) still
-- pick up the rounded border.
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.picker = opts.picker or {}
      opts.picker.sources = opts.picker.sources or {}
      opts.picker.sources.files = vim.tbl_deep_extend("force", opts.picker.sources.files or {}, {
        hidden = true,
        ignored = true,
      })
      opts.picker.sources.grep = vim.tbl_deep_extend("force", opts.picker.sources.grep or {}, {
        hidden = true,
        ignored = true,
      })

      opts.styles = opts.styles or {}
      opts.styles.terminal = vim.tbl_deep_extend("force", opts.styles.terminal or {}, {
        border = "rounded",
      })
    end,
  },
}
