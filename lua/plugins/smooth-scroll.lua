-- Smooth scrolling — neoscroll (ADR-0047 §C)
--
-- Animates <C-u>/<C-d>/<C-b>/<C-f>/<C-y>/<C-e> + zt/zz/zb so viewport jumps
-- glide instead of teleporting. Snacks' own scroll animation stays disabled
-- (see snacks-animated-scrolling-off.lua) — exactly one smooth-scroll animator
-- runs at a time.
--
-- Turn off with an override in lua/custom/plugins/:
--   return { { "karb94/neoscroll.nvim", enabled = false } }

return {
  "karb94/neoscroll.nvim",
  event = "VeryLazy",
  opts = {
    -- default `mappings` auto-bind <C-u>/<C-d>/<C-b>/<C-f>/<C-y>/<C-e>/zt/zz/zb
    easing = "quadratic", -- linear|quadratic|cubic|quartic|quintic|circular|sine
    duration_multiplier = 1.0, -- lower = snappier; raise for a slower glide
    hide_cursor = true, -- hide real cursor mid-scroll (plays fine with smear)
    respect_scrolloff = false,
    stop_eof = true,
    performance_mode = false, -- flip true on huge files to drop syntax-hl mid-scroll
  },
}
