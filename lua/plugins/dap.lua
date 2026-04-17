-- Debugging for Go (and anything else nvim-dap supports) using delve.
-- Minimalistic UI via nvim-dap-view (not nvim-dap-ui).
--
-- LazyVim's Go extra already pulls in `mfussenegger/nvim-dap` and
-- `leoluz/nvim-dap-go`; we extend them with keymaps, dap-view wiring,
-- and make sure `delve` is installed through Mason.

return {
  -- Core DAP: keymaps + sign glyphs.
  -- Note: dap-view is NOT listed as a dependency here — `dap-view`'s modules
  -- `require("dap")` at load time, so declaring it as a dep of nvim-dap
  -- creates a circular load. dap-view loads itself when its keymaps fire.
  {
    "mfussenegger/nvim-dap",
    keys = {
      -- Step / flow controls
      { "<F9>",  function() require("dap").continue()   end, desc = "Debug: Continue / Start" },
      { "<F8>",  function() require("dap").step_over()  end, desc = "Debug: Step Over" },
      { "<F7>",  function() require("dap").step_into()  end, desc = "Debug: Step Into" },
      { "<F10>", function() require("dap").step_out()   end, desc = "Debug: Step Out" },

      -- Breakpoints
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Debug: Toggle Breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Debug: Conditional Breakpoint" },
      { "<leader>dC", function() require("dap").clear_breakpoints() end, desc = "Debug: Clear Breakpoints" },

      -- Session control
      { "<leader>dc", function() require("dap").continue()  end, desc = "Debug: Continue / Start" },
      { "<leader>dr", function() require("dap").run_last()  end, desc = "Debug: Run Last" },
      { "<leader>dq", function() require("dap").terminate() end, desc = "Debug: Terminate" },
      { "<leader>dR", function() require("dap").restart()   end, desc = "Debug: Restart" },
    },
    config = function()
      -- Sign column glyphs
      vim.fn.sign_define("DapBreakpoint",          { text = "●", texthl = "DiagnosticError", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticError", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointRejected",  { text = "○", texthl = "DiagnosticWarn",  linehl = "", numhl = "" })
      vim.fn.sign_define("DapLogPoint",            { text = "◆", texthl = "DiagnosticInfo",  linehl = "", numhl = "" })
      vim.fn.sign_define("DapStopped",             { text = "▶", texthl = "DiagnosticWarn",  linehl = "Visual", numhl = "" })
    end,
  },

  -- Minimalistic inspection UI. Depends on nvim-dap (so it loads after it).
  -- Keymaps live here so pressing them lazy-loads dap-view.
  {
    "igorlfs/nvim-dap-view",
    dependencies = { "mfussenegger/nvim-dap" },
    keys = {
      { "<leader>dv", function() require("dap-view").toggle() end, desc = "Debug: Toggle View" },
      { "<leader>dw", function() require("dap-view").add_expr() end, desc = "Debug: Watch Expr (add)", mode = { "n", "v" } },
      { "<leader>de", function() require("dap-view").eval() end, desc = "Debug: Evaluate", mode = { "n", "v" } },
    },
    opts = {
      winbar = {
        show = true,
        sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl" },
        default_section = "scopes",
      },
      windows = {
        size = 12,
        terminal = {
          position = "right",
        },
      },
    },
    config = function(_, opts)
      local dap = require("dap")
      local dv  = require("dap-view")
      dv.setup(opts)

      -- Auto-open the inspection panel when a session starts, close on exit.
      dap.listeners.before.attach["dap-view-config"]           = function() dv.open() end
      dap.listeners.before.launch["dap-view-config"]           = function() dv.open() end
      dap.listeners.before.event_terminated["dap-view-config"] = function() dv.close() end
      dap.listeners.before.event_exited["dap-view-config"]     = function() dv.close() end
    end,
  },

  -- Delve adapter + helpers (attach to PID, debug test under cursor).
  {
    "leoluz/nvim-dap-go",
    ft = "go",
    dependencies = { "mfussenegger/nvim-dap" },
    keys = {
      { "<leader>da", function() require("dap-go").attach() end,          desc = "Debug: Attach to Process (delve)", ft = "go" },
      { "<leader>dt", function() require("dap-go").debug_test() end,      desc = "Debug: Debug Go Test",             ft = "go" },
      { "<leader>dT", function() require("dap-go").debug_last_test() end, desc = "Debug: Debug Last Go Test",        ft = "go" },
    },
    opts = {
      delve = {
        detached = vim.fn.has("win32") == 0,
      },
    },
  },

  -- Ensure delve is available.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "delve" })
    end,
  },
}
