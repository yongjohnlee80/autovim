local function toggle_terminal(slot)
  return function()
    Snacks.terminal.toggle(vim.o.shell, {
      count = slot,
      win = {
        width = 0.78,
        height = 0.78,
        row = 0.04 + ((slot - 1) * 0.03),
        col = 0.06 + ((slot - 1) * 0.04),
        title = (" Terminal %d "):format(slot),
        title_pos = "center",
      },
    })
  end
end

return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.styles = opts.styles or {}
      opts.styles.terminal = vim.tbl_deep_extend("force", opts.styles.terminal or {}, {
        border = "rounded",
      })
    end,
    keys = {
      { "<F1>", toggle_terminal(1), mode = { "n", "t" }, desc = "Terminal 1" },
      { "<F2>", toggle_terminal(2), mode = { "n", "t" }, desc = "Terminal 2" },
      { "<F3>", toggle_terminal(3), mode = { "n", "t" }, desc = "Terminal 3" },
      { "<F4>", toggle_terminal(4), mode = { "n", "t" }, desc = "Terminal 4" },
    },
  },
}
