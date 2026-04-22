local function toggle(slot)
  return function()
    require("utils.term_send").toggle(slot)
  end
end

local function toggle_codex()
  return function()
    require("utils.term_send").toggle_codex()
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
      { "<F1>", toggle(1), mode = { "n", "t" }, desc = "Terminal 1" },
      { "<F2>", toggle(2), mode = { "n", "t" }, desc = "Terminal 2" },
      { "<F3>", toggle(3), mode = { "n", "t" }, desc = "Terminal 3" },
      { "<F4>", toggle(4), mode = { "n", "t" }, desc = "Terminal 4" },
      { "<F5>", toggle_codex(), mode = { "n", "t" }, desc = "Codex" },
    },
  },
}
