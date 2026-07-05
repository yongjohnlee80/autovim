-- Cursor visibility — beacon flash + smear trail (ADR-0047 §A)
--
-- On a wide screen the block cursor is easy to lose, especially across
-- <C-l>/<C-h> window switches. Two complementary cues, both default-on:
--   * beacon.nvim       — a flash pulse on jumps + window-enter (WinEnter).
--   * smear-cursor.nvim — an animated trail, incl. across window/split switches.
--
-- Turn either off with an override in lua/custom/plugins/, e.g.
--   return { { "sphamba/smear-cursor.nvim", enabled = false } }

return {
  {
    "DanilaMihailov/beacon.nvim",
    event = "VeryLazy",
    opts = {
      min_jump = 10, -- min in-buffer jump (lines) that also flashes
      winblend = 60, -- slightly more opaque than the default 70
    },
  },
  {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
    opts = {
      smear_between_buffers = true, -- trail across window/split switches
      smear_between_neighbor_lines = true, -- trail within-buffer motion
      smear_insert_mode = true, -- set false if it feels busy while typing
      -- cursor_color left UNSET → auto-detected from the active highlight, so
      -- it tracks the current theme (incl. the omarchy overlay's theme
      -- hot-reload) instead of desyncing. Requires termguicolors (on).
    },
  },
}
