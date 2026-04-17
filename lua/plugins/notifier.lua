-- Make notifications stick around longer and map history view.
-- LazyVim routes `vim.notify` through snacks.nvim's notifier.
-- View history any time with `<leader>n` (LazyVim default) or `:lua Snacks.notifier.show_history()`.
-- Raw Neovim message log is always available via `:messages`.
-- Noice also keeps history via `:Noice` and `:Noice history`.

return {
  {
    "folke/snacks.nvim",
    opts = {
      notifier = {
        timeout = 6000, -- ms before a notification auto-dismisses (default 3000)
        style = "compact",
      },
    },
  },
}
