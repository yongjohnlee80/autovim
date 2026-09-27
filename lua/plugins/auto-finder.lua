-- auto-finder.nvim — multi-section side panel (files, repos, config, …).
--
-- Plugin source: github.com/yongjohnlee80/auto-finder.nvim. Pinned via
-- `version = "^0.5.0"` (caret). v0.5.0 retired the neo-tree fork: the files
-- and buffers slots are in-house (ADR-0200). v0.4.0 rebuilt the repos panel on
-- worktree.nvim and retired nvim-dbee. The 0.2 line was the auto-core consumer
-- migration (panel singleton via auto-core.ui.panel, state via
-- auto-core.state.namespace, file-filter prefs via auto-core.files,
-- live-refresh via auto-core.fs.watch, sections via
-- auto-core.ui.section + worktree:switched). v0.3.0 adds the ADR-0048
-- tests/debug panels' Config section, the `i` run-output view, `O`
-- toggle-all across views, and the debug Entry-Points rework
-- (run-in-terminal / debug / navigate / launch.json export).
--
-- For local development against ~/Source/Projects/nvim-plugins/auto-finder.nvim,
-- swap the spec line for:
--     dir = vim.fn.expand("~/Source/Projects/nvim-plugins/auto-finder.nvim"),
--     name = "auto-finder.nvim",
-- and lazy will use the working copy on `:Lazy reload auto-finder.nvim`.
--
-- The files and buffers slots are in-house since the ADR-0200 release: no
-- neo-tree fork, no nui / plenary. The upstream `neo-tree.nvim` stays
-- disabled in lua/plugins/disable-other-explorers.lua only because
-- LazyVim would otherwise open it as its own explorer.
--
-- Sections in v0.2: 0 = config (prompt REPL), 1 = files, 2 = repos
-- (registered repos × git worktrees). Numeric 0..9 in normal mode
-- inside the panel switches sections. Future: 3 = remote (SSH),
-- 4 = db.

return {
  {
    "yongjohnlee80/auto-finder.nvim",
    version = "^0.5.0",
    -- Dependencies:
    --   - web-devicons: file icons (optional for the plugin, wanted here)
    --   - auto-core.nvim: hard dep (panel / state / log / section /
    --     fs.watch / fs.scan / git.status / files surfaces)
    --
    -- NOT dependencies any more: `MunifTanjim/nui.nvim` and
    -- `nvim-lua/plenary.nvim` (the retired neo-tree fork's; plenary stays
    -- installed through auto-core), and `kndndrj/nvim-dbee` (ADR-0063 —
    -- autodb powers `dbase`; autodb itself is probed, not listed, so the
    -- finder stays usable without it).
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      "auto-core.nvim",
    },
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
      -- `min`/`max` bound `panel resize N` and the files slot's
      -- auto-expand. A pin (`panel resize N`) always wins.
      width = { default = 38, min = 25, max = 100 },
      default_section = 1,
      sections = { "config", "files", "repos" },
      -- The files slot. What the old `neo_tree` block configured is built
      -- in now: dotfiles and gitignored entries are shown (toggle with H,
      -- dotfiles dimmed), `.git` / `node_modules` are never listed, and
      -- auto-finder owns the directory hijack. Stated here so the choice
      -- is visible, not because the defaults differ.
      files = {
        follow = true,
        never_show = { ".git", "node_modules" },
        auto_expand_width = true,
      },
    },
  },
}
