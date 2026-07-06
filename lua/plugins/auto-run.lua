-- auto-run.nvim replaces gobugger.nvim (ADR-0048 Phase 4, parity gate
-- passed 2026-07-06). Unified run-config store (.auto-run/ two-tier),
-- env profiles, test discovery (go + jest), execution strategies, DAP
-- orchestration with per-repo breakpoint persistence, and the
-- <leader>r* / <leader>d* keymap set via default_keymaps().
-- launch.json is import-only (`:AutoRun import`); read-through covers
-- repos that haven't migrated yet.
return {
  {
    "yongjohnlee80/auto-run.nvim",
    -- Caret on the minor line so lazy auto-tracks every v0.1.x patch
    -- release without requiring an autovim bump per release. Matches
    -- the rest of the auto-family's `^0.X.0` convention.
    version = "^0.1.0",
    dependencies = {
      -- Hard dep: needs auto-core >= v0.1.61 (events.register_topics
      -- + auto-core.trust). The auto-core spec's own caret covers it.
      "yongjohnlee80/auto-core.nvim",
      "mfussenegger/nvim-dap",
      "leoluz/nvim-dap-go",
      "igorlfs/nvim-dap-view",
    },
    event = "VeryLazy",
    opts = {},
    config = function(_, opts)
      require("auto-run").setup(opts)
      require("auto-run").default_keymaps()
    end,
  },

  -- Ensure delve is available via Mason. auto-run's go debugging
  -- shells out to delve through dap-go; without it, every debug
  -- session fails. (Carried over from the gobugger spec.)
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "delve" })
    end,
  },

  -- nvim-dap has no `.setup()` function -- it's configured by mutating
  -- `dap.configurations.*` and `dap.adapters.*` directly. But
  -- LazyVim's lang extras (go / python) contribute an opts fragment to
  -- this plugin indirectly, which makes lazy.nvim auto-call
  -- `require("dap").setup(opts)` and crash with "attempt to call field
  -- 'setup' (a nil value)". Providing an explicit no-op config here
  -- short-circuits that auto-setup without disabling the plugin.
  -- (Carried over from the gobugger spec.)
  {
    "mfussenegger/nvim-dap",
    config = function() end,
  },
}
