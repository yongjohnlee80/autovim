-- AutoVIM branding for the startup splash.
--
-- LazyVim overrides snacks.dashboard's preset.header with its own
-- "LAZYVIM + Z's" ASCII block (see
-- ~/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/ui.lua). We
-- layer another opts override on top with the AUTOVIM block art, and
-- force the `SnacksDashboardHeader` highlight to white+bold so it
-- stands out from LazyVim's default pastel blue.
--
-- The highlight is re-applied on `ColorScheme` so it survives theme
-- switches — including Omarchy's hot-reload flow, which fires
-- `User LazyReload` → `:colorscheme <new>`, which in turn fires
-- `ColorScheme`.
return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = [[
 █████╗ ██╗   ██╗████████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██║   ██║██║████╗ ████║
███████║██║   ██║   ██║   ██║   ██║██║   ██║██║██╔████╔██║
██╔══██║██║   ██║   ██║   ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝]],
        },
      },
    },
    init = function()
      local set_hl = function()
        vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = "#ffffff", bold = true })
      end
      vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
      set_hl() -- initial paint; colorscheme may already have loaded
    end,
  },
}
