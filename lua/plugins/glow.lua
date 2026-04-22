-- Floating markdown preview via charmbracelet/glow.
-- `:Glow` renders the current buffer in a floating window. Close with
-- `q` or `<Esc>`. Requires the `glow` CLI on PATH (see README).
return {
  {
    "ellisonleao/glow.nvim",
    cmd = "Glow",
    ft = "markdown",
    opts = {
      border = "rounded",
      style = "dark",
      width_ratio = 0.85,
      height_ratio = 0.85,
    },
    keys = {
      {
        "<leader>mp",
        "<cmd>Glow<cr>",
        desc = "Markdown: Preview (glow)",
        ft = "markdown",
      },
    },
  },
}
