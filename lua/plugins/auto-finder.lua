-- auto-finder.nvim — multi-section file explorer with bundled neo-tree fork.
--
-- Plugin source: github.com/yongjohnlee80/auto-finder.nvim. Pinned via
-- `version = "^0.1.0"` (caret) so lazy.nvim auto-tracks v0.1.x patch
-- releases — currently v0.1.3 ships the bundled neo-tree fork and the
-- `cfg.neo_tree` wiring used below. Bump deliberately when a v0.2.x
-- arrives.
--
-- For local development against ~/Source/Projects/nvim-plugins/auto-finder.nvim,
-- swap the spec line for:
--     dir = vim.fn.expand("~/Source/Projects/nvim-plugins/auto-finder.nvim"),
--     name = "auto-finder.nvim",
-- and lazy will use the working copy on `:Lazy reload auto-finder.nvim`.
--
-- v0.1.3 ships its own forked neo-tree under
-- `auto-finder.nvim/lua/auto-finder/neotree/`. The upstream
-- `neo-tree.nvim` plugin is no longer required (and is hard-disabled
-- via lua/plugins/disable-other-explorers.lua so LazyVim's auto-imports
-- can't pull it back in transitively).
--
-- Sections in v0.1: 0 = config (prompt REPL), 1 = files, 2 = repos
-- (registered repos × git worktrees, v0.1.2+). Numeric 0..9 in normal
-- mode inside the panel switches sections. Future: 3 = remote (SSH),
-- 4 = db. See the ADR in
-- ~/Source/Documents/knowledge-base/projects/auto-finder/design-decisions/.

return {
  {
    "yongjohnlee80/auto-finder.nvim",
    version = "^0.1.0",
    -- Dependencies the bundled fork needs (these were neo-tree's
    -- own deps — picking them up directly now that we don't go
    -- through the upstream neo-tree.nvim plugin spec).
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
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
      -- `min`/`max` bound `panel resize N`. In dynamic mode, the
      -- forked renderer's `auto_expand_width` is free to grow the
      -- panel beyond `default`; `panel resize N` clamps hard at N
      -- (the renderer's pin check in render_tree skips the auto-
      -- expand branch when `state.user_width > 0`).
      width = { default = 38, min = 25, max = 100 },
      default_section = 1,
      sections = { "config", "files", "repos" },
      -- Forwarded to `auto-finder.neotree.setup()` — these are the
      -- options that used to live in `lua/plugins/neo-tree.lua`,
      -- routed here so they reach the FORK, not upstream's neo-tree.
      neo_tree = {
        window = {
          -- Let the forked renderer expand the panel beyond
          -- auto-finder's `cfg.width.default` when a filename is
          -- longer than the panel can hold. Won't shrink — the panel
          -- still respects auto-finder's `min`/`max`. A user pin
          -- (`panel resize N`) overrides auto-expand entirely
          -- regardless of this flag.
          auto_expand_width = true,
        },
        filesystem = {
          -- Auto-finder owns the directory-hijack flow via its
          -- one-shot VimEnter handler; neo-tree must stay out of it.
          hijack_netrw_behavior = "disabled",
          filtered_items = {
            -- Show dotfiles and gitignored files by default; mark
            -- them as visible-but-styled rather than hiding outright.
            visible = true,
            hide_dotfiles = false,
            hide_gitignored = false,
          },
          check_gitignore_in_search = false,
          components = {
            -- Highlight dotfiles (top-level `.foo` filenames) with a
            -- dimmer color so they don't compete with the content
            -- you'd typically want to find.
            name = function(config, node, state)
              local cc = require("auto-finder.neotree.sources.common.components")
              local result = cc.name(config, node, state)
              local name = node.name or ""
              if node.type ~= "directory" and name:sub(1, 1) == "." then
                result.highlight = "NeoTreeDotfile"
              end
              return result
            end,
          },
        },
      },
    },
  },
}
