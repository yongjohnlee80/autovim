-- Decide WHICH colorscheme AutoVim should apply, as a pure function.
--
-- The decision has three inputs that used to be spread across a git branch, an
-- autocmd, and a symlink: AutoVim's own persisted pick, whether this box runs
-- Omarchy, and which theme Omarchy currently reports. Keeping the rule pure
-- (no vim calls, no io) is what makes it assertable headlessly on any OS —
-- `tests/smoke.lua` drives every branch below without needing a macOS box or
-- an Omarchy install.
--
-- The rule (requirement 5):
--   * Not Omarchy → AutoVim's persisted pick, else `catppuccin-mocha`.
--   * Omarchy     → Omarchy's system theme, UNLESS AutoVim holds a pick that
--                   was made while Omarchy was on the same theme it is on now.
--
-- That last clause is the whole subtlety. On Omarchy the theme is applied by
-- Omarchy itself, which fires `ColorScheme` — so a naive "persist every
-- ColorScheme event" cache records Omarchy's own choice as though the user had
-- made it, and from then on the user is pinned to whatever Omarchy last set
-- and system theme switches silently stop working. (The old `omarchy` branch
-- dodged this by deleting the persist autocmd outright, which also threw away
-- the ability to override at all.) Stamping the cache with the Omarchy theme
-- that was active at save time separates the two cases: a stamp that still
-- matches means the user genuinely picked something else while on this system
-- theme; a stamp that has gone stale means the system theme moved on, and the
-- system wins again.

local M = {}

-- Requirement 5: every non-Omarchy platform defaults here.
M.FALLBACK = "catppuccin-mocha"

--- Decide the colorscheme.
--- @param s table
---   cached              string|nil  AutoVim's persisted colorscheme pick
---   cached_stamp        string|nil  Omarchy theme name active when it was saved
---   omarchy             boolean     is this an Omarchy box
---   omarchy_theme       string|nil  Omarchy's currently reported theme name
---   omarchy_colorscheme string|nil  colorscheme from Omarchy's own lazy spec
--- @return string name, string reason
function M.decide(s)
  s = s or {}

  if not s.omarchy then
    if s.cached then
      return s.cached, "autovim-cache"
    end
    return M.FALLBACK, "default"
  end

  -- An unstamped cache is ambiguous: it predates this mechanism, so we cannot
  -- tell a deliberate override from an echo of Omarchy's own application. On
  -- Omarchy the documented default is the system theme, so ambiguity resolves
  -- toward the system rather than silently pinning the user.
  if s.cached and s.cached_stamp and s.cached_stamp == s.omarchy_theme then
    return s.cached, "autovim-override"
  end

  if s.omarchy_colorscheme then
    return s.omarchy_colorscheme, "omarchy-system"
  end

  -- Omarchy is installed but has not materialised a usable theme spec. Fall
  -- back to any pick we hold before resorting to the distribution default.
  if s.cached then
    return s.cached, "autovim-cache"
  end
  return M.FALLBACK, "default"
end

--- Pull the colorscheme name out of an Omarchy `neovim.lua` lazy fragment.
--- Omarchy ships a spec list whose `LazyVim/LazyVim` entry carries
--- `opts.colorscheme`. Returns nil for any shape we do not recognise rather
--- than guessing — a wrong guess here is a broken editor on first launch.
--- @param spec table|nil
--- @return string|nil
function M.colorscheme_of(spec)
  if type(spec) ~= "table" then
    return nil
  end
  for _, entry in ipairs(spec) do
    if type(entry) == "table" and entry[1] == "LazyVim/LazyVim" then
      local cs = type(entry.opts) == "table" and entry.opts.colorscheme or nil
      if type(cs) == "string" and cs ~= "" then
        return cs
      end
    end
  end
  return nil
end

--- Read live state and decide. The single entry point for callers that want
--- "what should the colorscheme be right now" — both the lazy spec and
--- `:AutovimThemeFollowSystem` use this, so the rule cannot drift between them.
--- @param opts table|nil  `ignore_cache = true` answers "what would we pick if
---                        the user had never overridden", which is exactly what
---                        follow-system needs.
--- @return string name, string reason
function M.current(opts)
  opts = opts or {}
  local platform = require("utils.platform")
  local record = opts.ignore_cache and {} or require("utils.theme_cache").load_full()
  return M.decide({
    cached = record.name,
    cached_stamp = record.omarchy_stamp,
    omarchy = platform.is_omarchy(),
    omarchy_theme = platform.omarchy_theme_name(),
    omarchy_colorscheme = M.colorscheme_of(platform.omarchy_fragment()),
  })
end

return M
