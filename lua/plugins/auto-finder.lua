-- auto-finder.nvim — multi-section file explorer (config + files for v0.1).
--
-- Plugin source: github.com/yongjohnlee80/auto-finder.nvim. Pinned via
-- `version = "^0.1.0"` (caret) so lazy.nvim auto-tracks v0.1.x patch
-- releases without pulling a future v0.2.x — bump deliberately when a
-- major arrives.
--
-- For local development against ~/Source/Projects/nvim-plugins/auto-finder.nvim,
-- swap the spec line for:
--     dir = vim.fn.expand("~/Source/Projects/nvim-plugins/auto-finder.nvim"),
--     name = "auto-finder.nvim",
-- and lazy will use the working copy on `:Lazy reload auto-finder.nvim`.
--
-- Sections in v0.1: 0 = config (prompt REPL), 1 = files (neo-tree wrapper).
-- Numeric 0..9 in normal mode inside the panel switches sections.
-- Future: 2 = repos, 3 = remote (SSH), 4 = db. See ADR 0001 in the plugin
-- repo for the full design.

return {
  {
    "yongjohnlee80/auto-finder.nvim",
    version = "^0.1.0",
    dependencies = { "nvim-neo-tree/neo-tree.nvim" },
    cmd = { "AutoFinder", "AutoFinderFocus", "AutoFinderResize", "AutoFinderReset" },
    keys = {
      { "<leader>e",  "<cmd>AutoFinder<cr>",         desc = "Explorer (auto-finder)" },
      { "<leader>E",  "<cmd>AutoFinder!<cr>",        desc = "Explorer (auto-finder, force)" },
      -- Override LazyVim's `<leader>fe`/`<leader>fE` (which by default
      -- toggle a separate neo-tree window). Route them through
      -- AutoFinderFocus 1 so they open the panel and land on the
      -- files section. <leader>fE forces past the width-min check.
      { "<leader>fe", "<cmd>AutoFinderFocus 1<cr>",  desc = "Explorer files (auto-finder)" },
      { "<leader>fE", "<cmd>AutoFinder!<cr><cmd>AutoFinderFocus 1<cr>", desc = "Explorer files (auto-finder, force)" },
    },
    -- VimEnter fires once at startup; the plugin's directory-hijack
    -- one-shot needs to be loaded by then so `nvim .` lands in the
    -- panel instead of an empty `/path` buffer (netrwPlugin is
    -- disabled in lua/config/lazy.lua).
    event = "VimEnter",
    opts = {
      -- The panel is anchored to the left; auto-finder dropped the
      -- `side` option (the right slot is reserved for auto-agents
      -- and the <F5> terminal).
      --
      -- `default` is the panel's resting width when no pin is set;
      -- `min`/`max` bound `panel resize N`. In dynamic mode, neo-tree's
      -- auto_expand_width is free to grow the panel beyond `default`;
      -- `panel resize N` clamps hard at N.
      width = { default = 38, min = 25, max = 100 },
      default_section = 1,
      sections = { "config", "files" },
    },
  },
}
