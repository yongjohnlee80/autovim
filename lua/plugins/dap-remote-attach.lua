-- Connect to an already-running `dlv --headless --listen=:PORT` server.
--
-- Complements `<leader>da` (gobugger → dap-go's "Attach" config, mode="local"),
-- which picks a local PID and spawns dlv itself. That flow doesn't work when
-- dlv was started externally (e.g. `/run <app> --dlv`, or dlv-on-a-remote-box).
-- For those cases we need a DAP config with mode="remote".
--
-- Default port 2345 matches the starting port `/run --dlv` picks from the
-- 2345..2355 range. Override in the prompt if the auto-attach landed on a
-- different port (check `/tmp/<app>-dlv-*.log`).
return {
  {
    "mfussenegger/nvim-dap",
    dependencies = { "yongjohnlee80/gobugger.nvim" },
    keys = {
      {
        "<leader>dA",
        function()
          local input = vim.fn.input("dlv server port: ", "2345")
          local port = tonumber(input)
          if not port then
            vim.notify("dap-remote-attach: invalid port", vim.log.levels.WARN)
            return
          end
          require("dap").run({
            type = "go",
            name = ("Attach remote :%d"):format(port),
            mode = "remote",
            request = "attach",
            host = "127.0.0.1",
            port = port,
          })
        end,
        desc = "Debug: Attach to dlv server (remote)",
      },
    },
  },
}
