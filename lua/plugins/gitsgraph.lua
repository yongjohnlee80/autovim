-- gitsgraph.nvim — multi-repo git-graph dashboard.
--
-- Plugin source: github.com/yongjohnlee80/gitsgraph.nvim. To work
-- against a local copy temporarily, replace the `version` line with
-- `dir = vim.fn.expand("~/Source/Projects/nvim-plugins/gitsgraph.nvim")`.
--
-- Versioning: `version = "^0.1.0"` caret-pins to the v0.1.x line, so
-- lazy auto-updates within the line and refuses to cross to v0.2+
-- unprompted. Bump the caret only when the upstream plugin tags a new
-- minor.
--
-- Wraps isakbm/gitgraph.nvim. Don't configure gitgraph elsewhere —
-- gitsgraph re-setup()s it on every repo switch and will overwrite
-- competing configs.

return {
  {
    "yongjohnlee80/gitsgraph.nvim",
    version = "^0.1.0",
    dependencies = {
      "isakbm/gitgraph.nvim",
      -- diffview.nvim is intentionally NOT a dependency. gitsgraph's
      -- default <CR>-on-commit handler renders the diff in a self-
      -- contained float (see lua/gitsgraph/diff.lua) — diffview's
      -- tab-takeover model didn't fit the panel UX. To opt back in,
      -- add "sindrets/diffview.nvim" here and override on_select_commit
      -- in opts to call :DiffviewOpen.
    },
    cmd = { "GitsGraph", "GitsGraphToggle", "GitsGraphClose",
            "GitsGraphRefresh", "GitsGraphSetRoot" },
    keys = {
      { "<leader>gt", function() require("gitsgraph").toggle() end,
        desc = "gitsgraph: toggle multi-repo graph" },
    },
    opts = {},
  },
  -- Pulled transitively via dependencies, but pinned here so we can move
  -- the version forward independently if needed.
  {
    "isakbm/gitgraph.nvim",
    lazy = true,
  },
}
