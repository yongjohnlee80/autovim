-- Persist the user's current colorscheme to disk so it survives nvim
-- restarts. Backing the `theme-picker` + `ColorScheme` autocmd flow that
-- replaces LazyVim's hard-coded `opts.colorscheme = "catppuccin"` default.
--
-- Path: `stdpath("state")/current-theme.txt` (single-line, just the name).
-- No IGNORE list for preview-only hovers: Snacks' colorscheme picker emits
-- a ColorScheme event when the user cancels (restoring the previous
-- choice), so the last event we see is always the final choice — preview
-- churn is self-healing.

local M = {}

local function cache_path()
  return vim.fn.stdpath("state") .. "/current-theme.txt"
end

function M.save(name)
  if type(name) ~= "string" or name == "" then
    return
  end
  local ok, err = pcall(function()
    local path = cache_path()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fh = assert(io.open(path, "w"))
    fh:write(name .. "\n")
    fh:close()
  end)
  if not ok then
    vim.notify("theme_cache.save: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M.load()
  local fh = io.open(cache_path(), "r")
  if not fh then
    return nil
  end
  local name = fh:read("*l")
  fh:close()
  if not name then
    return nil
  end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  return name ~= "" and name or nil
end

function M.path()
  return cache_path()
end

return M
