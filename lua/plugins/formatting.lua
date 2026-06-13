-- Autoformat on save for TypeScript, Go, TOML, SQL, Python, and YAML.
-- LazyVim ships with conform.nvim and format-on-save enabled by default
-- (toggle globally with :LazyFormat or buffer-local with :LazyFormatDisable).
-- TypeScript/Go/Python formatters come from the lazyvim typescript/go/python extras.
-- Here we add TOML (taplo), SQL (sql_formatter), YAML (prettier), and ensure
-- all required binaries are installed via Mason.
return {
  -- Register formatters with conform for filetypes LazyVim doesn't cover.
  {
    "stevearc/conform.nvim",
    -- Override LazyVim's stock <leader>cF ("Format Injected Langs") to do a
    -- full forced buffer format instead. cF is our ONLY format key here:
    -- <leader>cf (lowercase) is taken by code-runner.lua → :RunFile. LazyVim
    -- binds cF to conform's "injected" formatter, which only touches fenced
    -- code blocks and is a no-op on prose/table docs — which is why pressing
    -- cF "did nothing" when trying to align a markdown table. Rebinding cF to
    -- a full force-format makes it work (and bypasses the markdown
    -- autoformat=false flag set in lua/custom/autocmds.lua).
    keys = {
      {
        "<leader>cF",
        function()
          LazyVim.format({ force = true })
        end,
        mode = { "n", "x" },
        desc = "Format (force)",
      },
    },
    opts = {
      formatters_by_ft = {
        toml = { "taplo" },
        sql = { "sql_formatter" },
        mysql = { "sql_formatter" },
        plsql = { "sql_formatter" },
        yaml = { "prettierd", "prettier", stop_after_first = true },
        -- Markdown: registered for ON-DEMAND formatting only (prettier aligns
        -- GFM tables + tidies the doc). Save-time autoformat is disabled for
        -- markdown in lua/custom/autocmds.lua so KB docs aren't rewritten on
        -- every save; format with <leader>cF / :LazyFormat when you want it.
        markdown = { "prettierd", "prettier", stop_after_first = true },
        -- Python: ruff is provided by the python extra, but pin it here so
        -- formatting uses ruff's import sort + formatter deterministically.
        python = { "ruff_organize_imports", "ruff_format" },
      },
    },
  },

  -- Make sure the formatter binaries get installed automatically.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "prettierd",     -- TypeScript/JavaScript/YAML (fast prettier daemon)
        "prettier",      -- fallback if prettierd isn't preferred
        "gofumpt",       -- Go
        "goimports",     -- Go imports
        "taplo",         -- TOML
        "sql-formatter", -- SQL
        "ruff",          -- Python (format + import sort, replaces black/isort)
      })
    end,
  },
}