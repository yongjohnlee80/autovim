-- F1..F5 dispatch through `utils.float_focus` so the same key that *opens*
-- an unfocused-but-visible terminal also *focuses* it (instead of hiding it
-- as the plain `term:toggle()` path used to). Only the focused-and-pressed
-- case still toggles off. See `utils/float_focus.lua` for the full spec.
local function focus_or_hide(slot)
  return function()
    require("utils.float_focus").focus_or_hide_slot(slot)
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
      { "<F1>", focus_or_hide(1), mode = { "n", "t" }, desc = "Terminal 1 (focus/hide)" },
      { "<F2>", focus_or_hide(2), mode = { "n", "t" }, desc = "Terminal 2 (focus/hide)" },
      { "<F3>", focus_or_hide(3), mode = { "n", "t" }, desc = "Terminal 3 (focus/hide)" },
      { "<F4>", focus_or_hide(4), mode = { "n", "t" }, desc = "Terminal 4 (focus/hide)" },
      { "<F5>", focus_or_hide(5), mode = { "n", "t" }, desc = "Codex (focus/hide)" },
    },
  },
}
