return {
  {
    "yongjohnlee80/worktree.nvim",
    -- Caret range: accept any 0.2.x patch/minor but lock out 0.3.0+ which
    -- may ship breaking changes. Bump the lower bound after releasing a
    -- feature you want pinned.
    version = "^0.2.2",
    event = "VeryLazy",
    opts = {
      -- Workspace-rooted LSPs that get stopped + re-attached when we
      -- switch worktrees. `vtsls` is LazyVim's default TS server (via
      -- extras.lang.typescript); `tsserver` is listed as a fallback in
      -- case the config ever reverts. Non-running clients return empty
      -- queries, so listing both is harmless.
      lsp_servers_to_restart = { "gopls", "vtsls", "tsserver" },
      bare_dir = ".git", -- match existing repos cloned with `git clone --bare <url> .git`
    },
    keys = {
      { "<leader>gw", function() require("worktree").pick() end, desc = "Worktree: switch" },
      { "<leader>gW", function() require("worktree").home() end, desc = "Worktree: back to root" },
      { "<leader>gA", function() require("worktree").add() end, desc = "Worktree: add" },
      { "<leader>gR", function() require("worktree").remove() end, desc = "Worktree: remove" },
      { "<leader>gC", function() require("worktree").clone() end, desc = "Worktree: clone" },
      { "<leader>gc", function() require("worktree").init() end, desc = "Worktree: init new project" },
    },
  },
}
