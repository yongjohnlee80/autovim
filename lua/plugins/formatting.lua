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
    opts = {
      formatters_by_ft = {
        toml = { "taplo" },
        sql = { "sql_formatter" },
        mysql = { "sql_formatter" },
        plsql = { "sql_formatter" },
        yaml = { "prettierd", "prettier", stop_after_first = true },
        -- Python: ruff is provided by the python extra, but pin it here so
        -- formatting uses ruff's import sort + formatter deterministically.
        python = { "ruff_organize_imports", "ruff_format" },
      },
    },
  },

  -- Make sure the formatter binaries get installed automatically.
  {
    "williamboman/mason.nvim",
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