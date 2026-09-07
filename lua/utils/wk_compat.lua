-- Narrow compatibility adapter around which-key's internal trigger
-- lifecycle (ADR-0091; spec: 2026-09-07-autovim-family-which-key-recovery).
--
-- which-key (pinned 3aab214) installs its `<leader>` popup trigger as a
-- buffer-local mapping, but its bookkeeping can desynchronize from the
-- actual mapping set: obsolete queued mode objects can delete a fresh
-- trigger, an externally deleted trigger leaves a false-positive registry
-- entry, and a cached mode is never re-inspected on later BufEnter. The
-- observed symptom is that `<leader>` silently stops opening the popup and
-- every leader binding degrades to literal key replay. Restart was the only
-- known recovery, which is unacceptable for sessions hosting long-running
-- terminal work.
--
-- which-key currently exposes no public API for "verify the real mapping
-- exists and rebuild the mode if not". Until it does, THIS file is the one
-- place that reaches into which-key internals; the guard consumes only the
-- functions exposed here. Everything is feature-detected and fails safe
-- (never touches mappings when the internals move). When upstream grows a
-- sufficient public reconciliation API, delete this adapter and the guard
-- together with it.
--
-- The recovery core was validated in isolation by the 2026-09-07 incident
-- investigation: retire suspended (queued) mode objects for the target
-- buffer/mode, clear that mode, and let a fresh Mode attach from the real
-- mapping set.

local M = {}

-- ── internal surface, feature-detected ────────────────────────────────────
-- Resolved lazily on every call: which-key is lazy-loaded, so requiring at
-- module-load time could load it too early (or fail entirely).

local function ok(name)
  return type(name) == "string" and package.loaded[name] ~= nil
end

--- Whether any which-key internals have been loaded into this process.
function M.available()
  return ok("which-key.buf") and ok("which-key.triggers")
end

--- Call a function with the internal modules, or return nil when they are
--- absent or shaped differently than this adapter understands.
local function with_internals(fn)
  if not M.available() then
    return nil
  end
  local ok_req, Buf = pcall(require, "which-key.buf")
  local ok_trig, Triggers = pcall(require, "which-key.triggers")
  local ok_state, State = pcall(require, "which-key.state")
  local ok_conf, Config = pcall(require, "which-key.config")
  if not (ok_req and ok_trig and ok_state and ok_conf) then
    return nil
  end
  if
    type(Buf.get) ~= "function"
    or type(Buf.clear) ~= "function"
    or type(Triggers.suspended) ~= "table"
    or type(State.state) ~= "nil"
  then
    -- State.state is a field that is nil between interactions; `type(...) == "nil"`
    -- guards the module table itself being nil.
    return nil
  end
  if type(Config) ~= "table" or type(Config.disable) ~= "table" then
    return nil
  end
  return fn(Buf, Triggers, Config)
end

-- ── key normalization ─────────────────────────────────────────────────────
-- The incident proved literal Space and "<Space>" must be treated as the
-- same key: which-key registers the trigger as "<Space>" while maparg and
-- buffer keymaps can present either representation.

--- Normalize a lhs to which-key's canonical (keytrans) representation.
function M.norm(lhs)
  local Util = require("which-key.util")
  return Util.norm(lhs)
end

--- Effective mapping info for `keys` in `mode` on `buf`, or nil when not
--- present. Checks the REAL mapping set (never the internal trigger
--- registry). Buffer-local mappings take precedence over global ones,
--- matching Vim's resolution order; global user mappings are visible too
--- so a user who has taken over `<leader>` globally is never fought.
function M.get_trigger(buf, mode, keys)
  local normed = M.norm(keys)
  local effective
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if M.norm(m.lhs) == normed then
      effective = m
    end
  end
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if M.norm(m.lhs) == normed then
      effective = m -- buffer-local wins
    end
  end
  return effective
end

--- True when the which-key trigger mapping itself (desc contains
--- "which-key-trigger") is present for `keys` in `mode` on `buf`.
function M.has_trigger(buf, mode, keys)
  local m = M.get_trigger(buf, mode, keys)
  return m ~= nil and (m.desc or ""):find("which-key-trigger", 1, true) ~= nil
end

--- True when a NON-which-key mapping effectively owns `keys` in `mode` on
--- `buf` — a real user/plugin mapping (global or buffer-local) we must
--- never overwrite.
function M.has_competing_mapping(buf, mode, keys)
  local m = M.get_trigger(buf, mode, keys)
  return m ~= nil
    and (m.desc or ""):find("which-key-trigger", 1, true) == nil
    and not require("which-key.util").is_nop(m.rhs)
end

--- Whether which-key is configured to skip this buffer (its own disable
--- lists). Respects the user's LazyVim-resolved opts verbatim.
function M.disabled_for(buf)
  return with_internals(function(Buf, _Triggers, Config)
    if not vim.api.nvim_buf_is_valid(buf) then
      return true
    end
    local ft = vim.bo[buf].filetype
    local bt = vim.bo[buf].buftype
    local dis_ft = type(Config.disable.ft) == "table" and Config.disable.ft or {}
    local dis_bt = type(Config.disable.bt) == "table" and Config.disable.bt or {}
    return vim.tbl_contains(dis_ft, ft) or vim.tbl_contains(dis_bt, bt)
  end) == true
end

-- ── recovery core ─────────────────────────────────────────────────────────
-- Retire suspended (queued) mode objects for this buffer+mode, clear the
-- cached mode, and let a fresh Mode attach from the actual mapping set.
-- This is the validated in-place recovery core; it works in the same
-- process without touching any user mapping.

---@param buf number
---@param mode string
---@return boolean repaired, string? reason
function M.rebuild_mode(buf, mode)
  return with_internals(function(Buf, Triggers)
    if not vim.api.nvim_buf_is_valid(buf) then
      return false, "buffer invalid"
    end
    if M.has_competing_mapping(buf, mode, " ") then
      return false, "competing mapping present"
    end
    -- Retire every suspended (queued) mode object that targets this
    -- buffer+mode: an obsolete queued object that runs after its
    -- replacement can delete the freshly installed trigger (the confirmed
    -- source defect). Clearing the cached mode below does NOT retire the
    -- queue entry, so this must happen first.
    for m in pairs(Triggers.suspended) do
      if m.buf and m.buf.buf == buf and m.mode == mode then
        Triggers.suspended[m] = nil
      end
    end
    -- Clear the cached mode (detaches its triggers) and rebuild from the
    -- real mapping set. `Buf.get` reattaches a fresh Mode; deferred
    -- attachment flushes on the event loop.
    Buf.clear({ buf = buf, mode = mode })
    local fresh = Buf.get({ buf = buf, mode = mode })
    if not fresh then
      return false, "mode did not reattach (disabled buffer?)"
    end
    return true
  end) or false,
    "which-key internals unavailable"
end

--- True when which-key is mid-interaction (popup open) or executing a macro.
function M.interaction_active()
  if require("which-key.util").in_macro() then
    return true
  end
  local ok_s, State = pcall(require, "which-key.state")
  return ok_s and State.state ~= nil
end

return M
