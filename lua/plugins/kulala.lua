-- kulala.nvim: Neovim HTTP client driven by `.http` files.
--
-- Per-project layout is scaffolded into `<project>/.rest/` via
-- `require("utils.rest").scaffold()` (keymap <leader>Rs, cmd :RestScaffold).
--
-- Env files use kulala's JSON format:
--   .rest/http-client.env.json          -- committed (non-secret)
--   .rest/http-client.private.env.json  -- gitignored (secrets)
--
-- No luarocks / Lua 5.1 build step required. Core deps: curl + tree-sitter.
-- Optional CLIs: jq (JSON fmt), grpcurl (gRPC), websocat (WS), xmllint (XML).

return {
  {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    init = function()
      vim.filetype.add({ extension = { http = "http", rest = "http" } })

      -- Kulala's parser is `kulala_http` but the filetype stays `http` so
      -- kulala's own `ft = { "http", "rest" }` lazy trigger still fires.
      -- Register the parser + append the queries dir to rtp eagerly (in
      -- `init`, before lazy-load) so LazyVim's FileType autocmd finds
      -- highlights on the FIRST .http buffer instead of the second.
      local kulala_ts = vim.fn.stdpath("data") .. "/lazy/kulala.nvim/lua/tree-sitter"
      vim.opt.rtp:append(kulala_ts)
      pcall(vim.treesitter.language.register, "kulala_http", { "http", "rest" })

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
    opts = {
      default_view = "body",
      default_env = "dev",
      debug = false,
      show_icons = "on_request",
      kulala_keymaps = true,
      winbar = true,
    },
    keys = {
      {
        "<leader>Rr",
        function()
          require("kulala").run()
        end,
        desc = "Rest: run request",
      },
      {
        "<leader>Rl",
        function()
          require("kulala").replay()
        end,
        desc = "Rest: replay last",
      },
      {
        "<leader>Ra",
        function()
          require("kulala").run_all()
        end,
        desc = "Rest: run all in buffer",
      },
      {
        "<leader>Rt",
        function()
          require("kulala").toggle_view()
        end,
        desc = "Rest: toggle headers/body view",
      },
      {
        "<leader>Re",
        function()
          require("utils.rest").env_select()
        end,
        desc = "Rest: select env from http-client.env.json",
      },
      {
        "<leader>RE",
        function()
          require("utils.rest").env_show()
        end,
        desc = "Rest: show current env",
      },
    },
  },

}
