-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

require("utils.float_focus").install_auto_hide()

-- Persist the current colorscheme whenever it changes so that the next
-- nvim start can hot-reload it (see `plugins/theme.lua`). Fires for
-- picker selection, direct `:colorscheme` calls, and Snacks' cancel-path
-- revert — which is exactly what we want (the final state wins).
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ThemeCachePersist", { clear = true }),
  callback = function(ev)
    require("utils.theme_cache").save(ev.match)
  end,
})

-- Initial `:colorscheme` applied during LazyVim setup renders with the wrong
-- background material under Ghostty's transparency/blur — it looks like bare
-- system vibrancy instead of the theme's bg. Re-applying the same colorscheme
-- after startup (what the picker does on selection) forces a full repaint that
-- renders correctly. So on VimEnter, artificially re-fire the cached theme.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("ThemeRepaintOnEnter", { clear = true }),
  callback = function()
    local name = vim.g.colors_name
    if name and name ~= "" then
      pcall(vim.cmd.colorscheme, name)
    end
  end,
})

-- IntelliJ Island Dark-style overrides for TS/TSX/JS/JSX. Treesitter captures
-- are language-scoped (e.g. `@keyword.typescript`), so setting them globally
-- only affects those filetypes. JSX uses the `tsx` parser.
local function island_dark_overrides()
  local orange    = "#CC7832"
  local fn_blue   = "#82AAFF"  -- function names: true blue, not cyan
  local purple    = "#9876AA"
  local green     = "#6A8759"
  local num_blue  = "#6897BB"
  local gray      = "#808080"
  local doc_green = "#4F7A4F"  -- darker green for /** */ doc comments

  local langs = { "typescript", "tsx", "javascript" }
  for _, lang in ipairs(langs) do
    vim.api.nvim_set_hl(0, "@keyword."             .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.function."    .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.modifier."    .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.coroutine."   .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.return."      .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.import."      .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.conditional." .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.repeat."      .. lang, { fg = orange, bold = true })
    vim.api.nvim_set_hl(0, "@keyword.operator."    .. lang, { fg = orange, bold = true })

    vim.api.nvim_set_hl(0, "@function."            .. lang, { fg = fn_blue })
    vim.api.nvim_set_hl(0, "@function.call."       .. lang, { fg = fn_blue })
    vim.api.nvim_set_hl(0, "@function.method."     .. lang, { fg = fn_blue })
    vim.api.nvim_set_hl(0, "@function.method.call." .. lang, { fg = fn_blue })
    vim.api.nvim_set_hl(0, "@variable.member."     .. lang, { fg = purple })
    vim.api.nvim_set_hl(0, "@string."              .. lang, { fg = green })
    vim.api.nvim_set_hl(0, "@number."              .. lang, { fg = num_blue })
    vim.api.nvim_set_hl(0, "@comment."             .. lang, { fg = gray, italic = true })
    vim.api.nvim_set_hl(0, "@comment.documentation." .. lang, { fg = doc_green, italic = true })
    vim.api.nvim_set_hl(0, "@string.documentation." .. lang, { fg = doc_green, italic = true })
  end
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("IslandDarkTSOverrides", { clear = true }),
  callback = island_dark_overrides,
})
island_dark_overrides()
