-- rest.nvim: Neovim-native REST client driven by `.http` files.
--
-- Per-project layout is scaffolded into `<project>/.rest/` via
-- `require("utils.rest").scaffold()` (keymap <leader>Rs, cmd :RestScaffold).
-- Secrets live in `.rest/env/local.env` (gitignored). `shared.env` and
-- `dev.env` are committed.
--
-- rest.nvim 3.x pulls its HTTP client from luarocks. On first install, lazy
-- will build rocks (`tree-sitter-http`, `lua-curl`, `nvim-nio`, ...). This
-- build needs Lua 5.1 binaries + headers even if Neovim itself runs luajit.
--
-- Arch: the AUR `lua51` package provides `/usr/bin/lua5.1` and
-- `/usr/include/lua5.1/`. Without it, `:Lazy build rest.nvim` fails with
-- `Failed finding Lua header lua.h`. Install it once, then
-- `:Lazy build rest.nvim` again.
--
-- If `:Rest` fails with missing modules at runtime, run
-- `:checkhealth rest_nvim`.

return {
  {
    "rest-nvim/rest.nvim",
    ft = { "http" },
    cmd = { "Rest" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    init = function()
      vim.g.rest_nvim = {
        client = "curl",
        env = {
          enable = true,
          pattern = "%.env$",
        },
        request = {
          skip_ssl_verification = false,
          hooks = {
            encode_url = true,
            user_agent = "rest.nvim",
            set_content_type = true,
          },
        },
        response = {
          hooks = {
            decode_url = true,
            format = true,
          },
        },
        ui = {
          winbar = true,
          keybinds = {
            prev = "H",
            next = "L",
          },
        },
        highlight = {
          enable = true,
          timeout = 750,
        },
      }

      -- Fallback: make sure *.http files pick up the http filetype even if
      -- rest.nvim's own ftdetect hasn't registered yet.
      vim.filetype.add({ extension = { http = "http" } })

      -- Global keymaps that don't require rest.nvim to be loaded.
      vim.keymap.set("n", "<leader>Rs", function()
        require("utils.rest").scaffold()
      end, { desc = "Rest: scaffold .rest/" })

      vim.keymap.set("n", "<leader>Rn", function()
        require("utils.rest").new_scratch()
      end, { desc = "Rest: new scratch .http" })

      vim.api.nvim_create_user_command("RestScaffold", function()
        require("utils.rest").scaffold()
      end, { desc = "Scaffold a .rest/ collection in the current project" })

      vim.api.nvim_create_user_command("RestNewScratch", function()
        require("utils.rest").new_scratch()
      end, { desc = "Create a timestamped scratch .http file under .rest/http/local/" })
    end,
    keys = {
      { "<leader>Rr", "<cmd>Rest run<cr>", desc = "Rest: run request" },
      { "<leader>Rl", "<cmd>Rest last<cr>", desc = "Rest: run last" },
      {
        "<leader>Re",
        function()
          require("utils.rest").env_select()
        end,
        desc = "Rest: select env from .rest/env/",
      },
      { "<leader>RE", "<cmd>Rest env show<cr>", desc = "Rest: show env" },
    },
  },

  -- Ensure the `http` tree-sitter parser is installed so rest.nvim can parse
  -- requests out of the buffer.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "http" })
      end
    end,
  },
}
