-- gobugger.nvim is the single source of truth for Go debugging in this
-- config. Wires dap / dap-go / dap-view, registers the full <leader>d*
-- keymap set via default_keymaps(), and ships the launch.json picker +
-- scaffolder + doctor.
return {
  {
    "yongjohnlee80/gobugger.nvim",
    version = "^0.1.0",
    dependencies = {
      "mfussenegger/nvim-dap",
      "leoluz/nvim-dap-go",
      "igorlfs/nvim-dap-view",
    },
    event = "VeryLazy",
    opts = {
      lsp_servers_to_restart = { "gopls", "vtsls", "tsserver" },
      bare_dir = ".git", -- match existing repos cloned with `git clone --bare <url> .git`
    },
    config = function(_, opts)
      require("gobugger").setup(opts)
      require("gobugger").default_keymaps()
    end,
  },

  -- Ensure delve is available via Mason. gobugger shells out to delve
  -- through dap-go; without it, every debug session fails.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "delve" })
    end,
  },
}
