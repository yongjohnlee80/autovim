-- Platform + variant detection for a SINGLE-BRANCH AutoVim.
--
-- AutoVim used to ship one git branch per environment (`main`, `mac-os`,
-- `omarchy`). Every OS-specific line lived in a branch delta, which meant
-- every fix to shared code had to be rebased into three siblings, and the
-- siblings drifted anyway (the `omarchy` branch never received `tests/`, and
-- lost `colors/system.lua` + `utils/theme_cache.lua` entirely). This module
-- replaces that with a runtime check so the OS deltas can live on `main`.
--
-- The probes are indirected through `M.probe` purely so tests can substitute
-- them — a headless run on Arch has to be able to assert the macOS branch and
-- the non-omarchy branch too. Production code never assigns to `M.probe`.

local M = {}

-- The real probes, defined ONCE. `reset_probes` re-copies from here rather
-- than restating the table, so a stub-and-restore cycle cannot drift from
-- production behaviour.
local DEFAULT_PROBES = {
  sysname = function()
    return ((vim.uv or vim.loop).os_uname()).sysname
  end,
  isdir = function(p)
    return vim.fn.isdirectory(vim.fn.expand(p)) == 1
  end,
  readable = function(p)
    return vim.fn.filereadable(vim.fn.expand(p)) == 1
  end,
  executable = function(e)
    return vim.fn.executable(e) == 1
  end,
  read_line = function(p)
    local fh = io.open(vim.fn.expand(p), "r")
    if not fh then
      return nil
    end
    local line = fh:read("*l")
    fh:close()
    if type(line) ~= "string" then
      return nil
    end
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    return line ~= "" and line or nil
  end,
}

-- Restore the real probes. Tests that stub `M.probe` call this in teardown.
function M.reset_probes()
  M.probe = vim.tbl_extend("force", {}, DEFAULT_PROBES)
end

M.reset_probes()

M.OMARCHY_ROOT = "~/.config/omarchy"
M.OMARCHY_THEME_SPEC = "~/.config/omarchy/current/theme/neovim.lua"
M.OMARCHY_THEME_NAME = "~/.config/omarchy/current/theme.name"

function M.sysname()
  return M.probe.sysname()
end

function M.is_macos()
  return M.sysname() == "Darwin"
end

function M.is_linux()
  return M.sysname() == "Linux"
end

-- Mirrors `install.sh`'s `pick_branch` test so the runtime check and the
-- installer agree on what "this is an Omarchy box" means. Keep them in step.
function M.is_omarchy()
  if not M.is_linux() then
    return false
  end
  return M.probe.isdir(M.OMARCHY_ROOT) or M.probe.executable("omarchy")
end

-- Path to Omarchy's own lazy spec fragment, or nil when Omarchy is absent or
-- has not materialised a current theme. Presence of the ROOT does not imply
-- presence of the SPEC — a partially provisioned box has one without the
-- other, so callers must handle nil rather than assume.
function M.omarchy_theme_spec()
  if not M.is_omarchy() then
    return nil
  end
  return M.probe.readable(M.OMARCHY_THEME_SPEC) and M.OMARCHY_THEME_SPEC or nil
end

-- The name Omarchy reports for its active theme (`current/theme.name`). Used
-- as the stamp that tells an AutoVim theme override apart from a system theme
-- that has since moved on; see `utils.theme_resolve`.
function M.omarchy_theme_name()
  if not M.is_omarchy() then
    return nil
  end
  return M.probe.read_line(M.OMARCHY_THEME_NAME)
end

-- Omarchy's lazy fragment, parsed, or nil.
--
-- Read with `loadfile` + `pcall` because this is a file we do not own: a theme
-- switch caught mid-write must degrade to the default rather than abort config
-- load. This is the ONLY place that reads the fragment — `theme.lua` and
-- `:AutovimThemeFollowSystem` both come through here.
function M.omarchy_fragment()
  local path = M.omarchy_theme_spec()
  if not path then
    return nil
  end
  local chunk = loadfile(vim.fn.expand(path))
  if not chunk then
    return nil
  end
  local ok, spec = pcall(chunk)
  if not ok or type(spec) ~= "table" then
    return nil
  end
  return spec
end

return M
