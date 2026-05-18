-- nvim-dbee — schema-aware DB UI, the AutoVim-managed successor to the
-- lazysql float (retired in v0.3.10).
--
-- Surface:
--   - `:Dbee` toggles the dbee UI (drawer + editor + result panes).
--   - The auto-finder dbase section mounts the dbee drawer inside the
--     panel. Press `<CR>` on a connection node to set it active and
--     mount the companion editor/result panes; press `o` to toggle
--     expand/collapse on the schema tree.
--   - SQL scratchpads get schema-aware completion via cmp-dbee
--     (bridged into blink.cmp through blink.compat).
--
-- IMPORTANT — setup ownership.
--   `require("dbee").setup(...)` is called by
--   `auto-finder.sections._dbase_setup` on first mount. Do NOT add a
--   `config` function on the `kndndrj/nvim-dbee` entry below — two
--   setups will collide (drawer source list duplicates, connection
--   state goes weird).
--
-- IMPORTANT — `build` hook.
--   The `build` step downloads dbee's Go binary so `:Lazy sync` lands
--   users with a ready-to-run install. Without it, the user has to
--   `:Dbee install` manually. We keep it on the top-level entry so it
--   runs even when auto-finder is lazy-loaded.

return {
  -- The DB UI itself.
  {
    "kndndrj/nvim-dbee",
    build = function()
      require("dbee").install()
    end,
  },

  -- Tree-sitter SQL parser — cmp-dbee uses TS to resolve table aliases
  -- and CTEs in the current scratchpad. Without `sql` installed,
  -- cmp-dbee's `queries.lua` errors with `attempt to index local
  -- 'parser' (a nil value)`.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "sql" })
    end,
  },

  -- Schema-aware SQL completion source. Reads the dbee handler's
  -- active connection and emits table / column / alias / CTE
  -- candidates.
  {
    "MattiasMTS/cmp-dbee",
    dependencies = { "kndndrj/nvim-dbee" },
    ft = "sql",
    opts = {},
  },

  -- nvim-cmp → blink.cmp adapter. cmp-dbee is written against
  -- nvim-cmp's source API; blink.compat exposes it to blink.cmp.
  {
    "saghen/blink.compat",
    opts = {},
  },

  -- Wire cmp-dbee in as a blink source, scoped to `sql` files so the
  -- provider doesn't fire in unrelated buffers. `score_offset = 100`
  -- nudges schema matches above generic buffer matches.
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        per_filetype = {
          sql = { "dbee", "buffer", "snippets", "path" },
        },
        providers = {
          dbee = {
            name = "cmp-dbee",
            module = "blink.compat.source",
            score_offset = 100,
          },
        },
      },
    },
  },
}