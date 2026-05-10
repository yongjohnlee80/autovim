-- worktree.nvim — bare-repo + sibling-worktree workspace manager.
--
-- Plugin source: github.com/yongjohnlee80/worktree.nvim. Pinned via
-- `version = "^0.4.0"` (caret) — v0.4.0 is the auto-core consumer
-- release that also absorbed the multi-repo graph dashboard from the
-- now-archived gitsgraph.nvim. Future v0.4.x releases are additive-
-- only per the auto-core-maintenance convention.
--
-- For local development against the working copy:
--     dir = vim.fn.expand("~/Source/Projects/nvim-plugins/worktree.nvim/main"),
--     name = "worktree.nvim",
-- (worktree.nvim is itself in a bare-repo worktree layout, so the
-- runnable lua tree lives under `main/lua/`, not `lua/` at the
-- container root.)

return {
  {
    "yongjohnlee80/worktree.nvim",
    version = "^0.4.0",
    -- Dependencies:
    --   - auto-core.nvim: hard dep as of v0.4.0 (canonical
    --     git.worktree, ui.float.multi, lsp.reset, git.fetch /
    --     git.pull / git.worktree.destroy mutating ops).
    --   - isakbm/gitgraph.nvim: required by the worktree.graph view
    --     (multi-repo dashboard absorbed from gitsgraph.nvim in
    --     v0.4.0). Soft-dep at runtime — when missing, the middle
    --     pane shows a hint pointing at auto-core.git.graph.show_diff.
    dependencies = {
      "auto-core.nvim",
      "isakbm/gitgraph.nvim",
    },
    -- :WorktreeGraph + :WorktreeGraphRefresh added in v0.4.0 (graph
    -- view absorbed from gitsgraph.nvim per ADR 0007 Phase 4). cmd
    -- gates lazy-loading on the user commands; keys gates on the
    -- bindings below.
    cmd = {
      "WorktreePick", "WorktreeHome", "WorktreeAdd", "WorktreeRemove",
      "WorktreeClone", "WorktreeInit",
      "WorktreeGraph", "WorktreeGraphRefresh",
    },
    event = "VeryLazy",
    opts = {
      -- Additive: stack-detection picks the relevant servers
      -- automatically (go.mod → gopls; package.json → ts_ls/eslint;
      -- pyproject.toml → pyright; etc.); this list is folded in as
      -- `extra_servers` for cases where a server isn't keyed off any
      -- of the standard project markers. `vtsls` is LazyVim's default
      -- TS server (via extras.lang.typescript); `tsserver` is listed
      -- as a fallback in case the config ever reverts. Non-running
      -- clients return empty queries, so listing both is harmless.
      lsp_servers_to_restart = { "gopls", "vtsls", "tsserver" },
      bare_dir = ".git", -- match existing repos cloned with `git clone --bare <url> .git`
      integrations = {
        -- Per-worktree session save/load via folke/persistence.nvim:
        -- every <leader>gw / <leader>gW saves the old cwd's session and
        -- restores the new cwd's. LazyVim ships persistence.nvim as a
        -- core plugin so no extra install is needed.
        persistence = true,
      },
    },
    keys = {
      { "<leader>gw", function() require("worktree").pick() end,         desc = "Worktree: switch" },
      { "<leader>gW", function() require("worktree").home() end,         desc = "Worktree: back to root" },
      { "<leader>gA", function() require("worktree").add() end,          desc = "Worktree: add" },
      { "<leader>gR", function() require("worktree").remove() end,       desc = "Worktree: remove" },
      { "<leader>gC", function() require("worktree").clone() end,        desc = "Worktree: clone" },
      { "<leader>gc", function() require("worktree").init() end,         desc = "Worktree: init new project" },
      -- Multi-repo graph dashboard. Inherits the keybinding from
      -- gitsgraph.nvim (now archived; absorbed into worktree.graph
      -- as of v0.4.0) so muscle memory carries over verbatim.
      { "<leader>gt", function() require("worktree").graph.toggle() end, desc = "Worktree: multi-repo graph" },
    },
  },
  -- isakbm/gitgraph.nvim — pulled transitively via the dependencies
  -- above, but pinned here so we can move its version forward
  -- independently if needed.
  {
    "isakbm/gitgraph.nvim",
    lazy = true,
  },
}
