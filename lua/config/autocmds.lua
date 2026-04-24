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
