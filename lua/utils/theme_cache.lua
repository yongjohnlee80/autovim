-- Persist the user's current colorscheme to disk so it survives nvim
-- restarts. Backing the `theme-picker` + `ColorScheme` autocmd flow that
-- replaces LazyVim's hard-coded `opts.colorscheme = "catppuccin"` default.
--
-- Path: `stdpath("state")/current-theme.txt`.
-- No IGNORE list for preview-only hovers: Snacks' colorscheme picker emits
-- a ColorScheme event when the user cancels (restoring the previous
-- choice), so the last event we see is always the final choice — preview
-- churn is self-healing.
--
-- FORMAT (v2, backward compatible):
--   line 1: colorscheme name
--   line 2: `omarchy=<theme>`   (optional)
--
-- Line 2 stamps which Omarchy system theme was active when the pick was
-- saved, so `utils.theme_resolve` can tell a deliberate override from an echo
-- of Omarchy's own theme application. A v1 file (name only) still loads; it
-- simply carries no stamp, which `theme_resolve` treats as ambiguous and
-- resolves toward the system theme on Omarchy.

local M = {}

-- Test seam: point the cache at a scratch file so a suite can exercise the
-- read/write/clear cycle without touching the user's real saved theme.
M._path_override = nil

local function cache_path()
  return M._path_override or (vim.fn.stdpath("state") .. "/current-theme.txt")
end

--- @param name string          colorscheme to remember
--- @param omarchy_stamp string|nil  Omarchy theme name active right now
function M.save(name, omarchy_stamp)
  if type(name) ~= "string" or name == "" then
    return
  end
  local ok, err = pcall(function()
    local path = cache_path()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fh = assert(io.open(path, "w"))
    fh:write(name .. "\n")
    if type(omarchy_stamp) == "string" and omarchy_stamp ~= "" then
      fh:write("omarchy=" .. omarchy_stamp .. "\n")
    end
    fh:close()
  end)
  if not ok then
    vim.notify("theme_cache.save: " .. tostring(err), vim.log.levels.WARN)
  end
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Full record: `{ name = string|nil, omarchy_stamp = string|nil }`.
function M.load_full()
  local fh = io.open(cache_path(), "r")
  if not fh then
    return {}
  end
  local lines = {}
  for line in fh:lines() do
    lines[#lines + 1] = line
  end
  fh:close()

  local name = lines[1] and trim(lines[1]) or nil
  if name == "" then
    name = nil
  end

  local stamp
  for i = 2, #lines do
    local v = trim(lines[i]):match("^omarchy=(.+)$")
    if v then
      stamp = trim(v)
      break
    end
  end
  if stamp == "" then
    stamp = nil
  end

  return { name = name, omarchy_stamp = stamp }
end

--- Just the remembered colorscheme name (v1 callers).
function M.load()
  return M.load_full().name
end

function M.path()
  return cache_path()
end

--- Forget the pick entirely, so the next start falls back to the platform
--- default (Omarchy's system theme, or `catppuccin-mocha`). Backs
--- `:AutovimThemeFollowSystem`.
function M.clear()
  local ok, err = pcall(os.remove, cache_path())
  if not ok then
    vim.notify("theme_cache.clear: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return true
end

return M
