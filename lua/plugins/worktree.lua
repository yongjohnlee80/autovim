return {
  {
    "yongjohnlee80/worktree.nvim",
    event = "VeryLazy",
    opts = {
      lsp_servers_to_restart = { "gopls" },
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
