-- Cursor visibility — beacon flash (ADR-0047 §A)
--
-- On a wide screen the block cursor is easy to lose, especially across
-- <C-l>/<C-h> window switches. beacon.nvim flashes a pulse at the cursor:
-- always on WinEnter/FocusGained, and on a CursorMoved that clears `min_jump`
-- in BOTH screen row (`winline()`) and buffer line (`line('.')`) — so a jump
-- has to move the cursor on screen as well as through the file.
--
-- The flash is one floating window over a shared scratch buffer, faded by a
-- timer that raises `winblend` and shrinks the width until it closes itself.
-- Measured at these settings: ~330 ms, one window, closes cleanly.
--
-- Turn it off with an override in lua/custom/plugins/, e.g.
--   return { { "DanilaMihailov/beacon.nvim", enabled = false } }
--
-- smear-cursor.nvim was REMOVED 2026-09-08. It was the second cue here, and
-- the two overlapped: beacon already covers the case ADR-0047 §A names, so the
-- trail was paying a per-motion cost for a cue we already had.
--
-- What it actually cost, measured rather than assumed (see the PR):
--
--   * an animation loop at `time_interval = 17` ms — ~59 fps for the DURATION
--     of every motion, and autovim had `smear_insert_mode = true`, so it also
--     ran while typing;
--   * during a smear it draws floats at `windows_zindex = 300`, above most
--     floating UI, so the animation overlaps popups while it plays.
--
-- What it did NOT cost, stated because an earlier draft of this file claimed
-- otherwise and the claim was wrong: it does NOT hold 50 visible floats for
-- the life of the session. `max_kept_windows = 50` caps a REUSE POOL. Windows
-- past the cap are closed; those kept are set `hide = true`, so they render
-- nothing while idle and sit nowhere in the float stack. Measured: 0 floats
-- after setup, 3 (all hidden) once a burst of 300 moves had settled.
--
-- Its lazy-lock.json entry was removed in the same commit. A lock entry whose
-- spec is gone is the "ghost entry" shape release playbook §4d warns about, and
-- tests/cursor-visibility.lua now asserts both halves stay gone.

return {
  {
    "DanilaMihailov/beacon.nvim",
    event = "VeryLazy",
    opts = {
      min_jump = 10, -- min jump (lines) that also flashes; see the AND above
      winblend = 60, -- slightly more opaque than the default 70
    },
  },
}
