-- Colorscheme selection, unified across every platform on ONE branch.
--
-- History: the `omarchy` branch replaced this file with a SYMLINK to
-- `~/.config/omarchy/current/theme/neovim.lua`, which is why a per-OS branch
-- existed at all — a symlink is a tracked file, so it cannot be applied
-- conditionally. This version reads that same fragment at RUNTIME instead.
--
-- ── DO NOT INTERCEPT WHAT YOU ARE NOT OVERRIDING ────────────────────────────
-- The first version of this file always replaced Omarchy's
-- `LazyVim/LazyVim opts.colorscheme` STRING with a function of our own that
-- resolved and applied the colorscheme itself. That was the bug: it took over
-- the exact job Omarchy used to own, and in doing so lost everything LazyVim
-- does for a string colorscheme — loading the providing plugin, and its own
-- error handling. An Omarchy theme whose plugin AutoVim does not ship (10 of
-- Omarchy's 19 do not) then failed to apply and silently became
-- `catppuccin-mocha`: the user chose a system theme and got someone else's
-- default.
--
-- So: when the answer is "follow the system theme", Omarchy's fragment is
-- returned **verbatim** and we add nothing. Behaviour is then identical to the
-- old symlink, because it IS the old symlink's content, reaching LazyVim by the
-- same path. We only substitute a colorscheme when the user has actually chosen
-- one here — and even then we hand LazyVim a plain string, never a function, so
-- the loading path is LazyVim's in every case.
--
-- Requirement 5: Omarchy follows the system theme unless overridden here; every
-- other platform defaults to `catppuccin-mocha`.

local platform = require("utils.platform")
local resolve = require("utils.theme_resolve")

local fragment = platform.omarchy_fragment()
local name, reason = resolve.current()

-- Surfaced for debugging and for the theme picker, which needs to know whether
-- the current look is a system theme or an explicit override.
vim.g.autovim_theme_name = name
vim.g.autovim_theme_reason = reason

-- Following Omarchy's system theme: hand its fragment through untouched.
if reason == "omarchy-system" and fragment then
  return fragment
end

-- Otherwise: keep Omarchy's plugin declarations (so a theme it named is still
-- installable) but state our own colorscheme. Dropping only its
-- `LazyVim/LazyVim` entry is the minimum interception that expresses an
-- override.
local specs = {}
if fragment then
  for _, entry in ipairs(fragment) do
    if type(entry) == "table" and entry[1] and entry[1] ~= "LazyVim/LazyVim" then
      specs[#specs + 1] = entry
    end
  end
end

specs[#specs + 1] = {
  "LazyVim/LazyVim",
  -- A STRING, deliberately. LazyVim loads the providing plugin and reports
  -- failure itself; a function here would re-implement both, worse.
  opts = { colorscheme = name },
}

return specs
