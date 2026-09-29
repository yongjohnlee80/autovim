-- The line a debug session is stopped on, made easy to find.
--
-- nvim-dap marks it with the `DapStopped` sign, whose line highlight is
-- `debugPC` (LazyVim's dap setup points it at `DapStoppedLine` instead). Themes
-- paint that line faintly: catppuccin-mocha uses #11111b, DARKER than its own
-- #1e1e2e background, so the stopped line nearly vanishes (Johno, 2026-09-29:
-- "highlight where we are with more bright color background").
--
-- Only the BACKGROUND of those two groups changes. The colour is derived from
-- the active theme on every ColorScheme — 35% of its warning colour blended
-- into its normal background — because AutoVim ships many themes, and a
-- colour is designed for the surface it is painted on (KB convention
-- tui-theme-colours): a fixed bright colour that reads on a dark theme
-- washes out on a light one. A theme with no normal background (transparent)
-- falls back to its Visual background.

local M = {}

---How far the warning colour is blended into the background (0..1).
M.BLEND = 0.35

---The groups the stopped line is drawn with.
M.GROUPS = { "debugPC", "DapStoppedLine" }

---`a` blended toward `b`: each channel `b + t·(a − b)`, rounded.
---@param a integer  24-bit colour
---@param b integer  24-bit colour
---@param t number
---@return integer
function M.blend(a, b, t)
  local out = 0
  for shift = 16, 0, -8 do
    local ca = math.floor(a / 2 ^ shift) % 256
    local cb = math.floor(b / 2 ^ shift) % 256
    out = out * 256 + math.floor(cb + t * (ca - cb) + 0.5)
  end
  return out
end

local function hl(name)
  local ok, v = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and v or {}
end

---The background for the stopped line under the active theme, or nil when
---the theme gives nothing to derive it from.
---@return integer?
function M.color()
  local bg = hl("Normal").bg
  local accent = hl("DiagnosticWarn").fg
  if bg and accent then return M.blend(accent, bg, M.BLEND) end
  return hl("Visual").bg
end

---Set the stopped line's background for the active theme.
function M.apply()
  local bg = M.color()
  if not bg then return end
  -- Replace the background only; whatever else the theme set (a foreground,
  -- bold) stays. A group that is a link keeps its resolved attributes.
  for _, g in ipairs(M.GROUPS) do
    local cur = hl(g)
    cur.bg = bg
    vim.api.nvim_set_hl(0, g, cur)
  end
end

---Apply now and after every colorscheme change.
function M.install()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("AutovimDebugLine", { clear = true }),
    callback = function() M.apply() end,
  })
  M.apply()
end

return M
