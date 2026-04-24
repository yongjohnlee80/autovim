-- "system" pseudo-theme: clear all nvim-imposed highlights so the terminal
-- emulator's own palette and background show through. This is what an
-- untouched nvim looks like — plus `Normal` / `NormalFloat` etc. forced to
-- `NONE` for transparency (so Ghostty's translucent backdrop shines).
--
-- Selected the same way as any other colorscheme: `:colorscheme system` or
-- through the <leader>ut picker. `utils.theme_cache` persists it.

vim.cmd("hi clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "system"

-- Core "window" groups — force transparent so the terminal bg wins.
local transparent = {
  "Normal",
  "NormalNC",
  "NormalFloat",
  "FloatBorder",
  "FloatTitle",
  "SignColumn",
  "LineNr",
  "CursorLineNr",
  "EndOfBuffer",
  "FoldColumn",
  "MsgArea",
  "TabLine",
  "TabLineFill",
  "StatusLine",
  "StatusLineNC",
  "WinBar",
  "WinBarNC",
  "WinSeparator",
  "VertSplit",
}
for _, group in ipairs(transparent) do
  vim.api.nvim_set_hl(0, group, { bg = "NONE", ctermbg = "NONE" })
end
