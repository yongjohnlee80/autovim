-- Floating markdown preview via charmbracelet/glow.
-- `:Glow` renders the current buffer in a floating window. Close with
-- `q` or `<Esc>`. Requires the `glow` CLI on PATH (see README).
return {
  {
    "ellisonleao/glow.nvim",
    cmd = "Glow",
    ft = "markdown",
    init = function()
      -- glow.nvim spawns glow via vim.loop.spawn with a piped stdout (not
      -- a PTY). charmbracelet/termenv detects the missing TTY and strips
      -- all ANSI styling -- you'd see raw text with structural layout but
      -- no colors / syntax highlighting. CLICOLOR_FORCE=1 is termenv's
      -- documented override to emit ANSI regardless.
      vim.env.CLICOLOR_FORCE = "1"
    end,
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
