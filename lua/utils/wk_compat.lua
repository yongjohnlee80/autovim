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
  -- The result is captured, not returned inline. `return with_internals(...) or
  -- false, "…"` reads like a fallback but is not one: `f() or false` truncates
  -- f() to ONE value, so the inner reason was discarded and the literal
  -- "which-key internals unavailable" was returned as the reason for EVERY
  -- outcome — including success and "competing mapping present". Every
  -- `repair failed for buffer N: which-key internals unavailable` warning in
  -- the wild was therefore unattributed: the string named the one cause the
  -- code could not actually have been in (the internals were plainly available,
  -- or `with_internals` would not have run the body).
  local repaired, reason = with_internals(function(Buf, Triggers)
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
  end)
  if repaired == nil then
    return false, "which-key internals unavailable"
  end
  return repaired, reason
end

-- ── interaction diagnosis ─────────────────────────────────────────────────
-- Two different things used to answer to one name. `"which-key interaction or
-- macro active"` covered a user recording a macro (respect it) and a which-key
-- State object orphaned by an interaction that never cleaned up (must be
-- reaped, or the guard is deadlocked: it reports BROKEN on every idle tick and
-- refuses to rebuild, forever). Johno hit exactly that, and the only escape was
-- a hand-typed Lua one-liner.
--
-- The mechanism, read out of the pinned which-key source rather than inferred:
--
--   * `triggers.M.schedule()` is what re-attaches suspended triggers, and its
--     drain callback begins `if Util.in_macro() then return vim.defer_fn(...)`.
--     So while ANY macro is recording or executing, which-key will not
--     re-install the `<leader>` trigger at all. A recording left running (a `q`
--     that was never closed) therefore keeps the trigger missing AND — through
--     `in_macro()` below — keeps the guard from repairing it. Both halves of
--     the deadlock come from the same latched register, which is why Johno's
--     manual snippet had to stop the recording before anything else worked.
--   * `state.M.start()` sets `M.state` and then, on the immediately-executing
--     path (`if not M.check(M.state) then return true end`), returns with
--     `M.state` STILL SET after `M.execute` has already called
--     `Triggers.suspend(state.mode)`. `M.state` is cleared by `M.stop()`, which
--     the ModeChanged autocmd drives — so an action that never leaves normal
--     mode can leave the field latched with no popup on screen.
--
-- REFERENCE: ~/.local/share/nvim/lazy/which-key.nvim/lua/which-key/{state,triggers,util}.lua
-- at the pinned 3aab214.

local uv = vim.uv or vim.loop

--- How stale a State object must be before it is treated as orphaned rather
--- than live. `timeoutlen * 2` follows which-key's own timing (its `State.check`
--- compares elapsed against a single `timeoutlen`), with a 2s floor so a tiny
--- `timeoutlen` cannot make a live interaction look abandoned.
local function stale_after_ms()
  local tl = tonumber(vim.o.timeoutlen) or 1000
  return math.max(2000, tl * 2)
end

--- Structured cause of a blocked repair, or nil when nothing is in progress.
---
--- Causes, most specific first:
---   "macro-recording"  detail = register — a user action; never stomped
---                      automatically, and the thing that also stops which-key
---                      re-attaching its own triggers.
---   "macro-executing"  detail = register — transient; the replay will end.
---   "popup-open"       the which-key window is genuinely on screen.
---   "state-live"       `State.state` is set with no window yet, and young
---                      enough to be a deferred popup mid-flight — or of an
---                      unrecognized shape, which is treated as live because
---                      an unageable state is one we cannot prove is stale —
---                      or the window's validity could not be observed at all,
---                      which is an unknown and never an absence.
---   "state-orphaned"   `State.state` is set, a window was OBSERVED absent, and it has
---                      been that way longer than `stale_after_ms()`. This is
---                      the deadlock; it is not an interaction.
---@return string? cause, string? detail
function M.interaction_reason()
  local ok_u, Util = pcall(require, "which-key.util")
  if ok_u and type(Util.in_macro) == "function" then
    local recording = vim.fn.reg_recording()
    if recording ~= "" then
      return "macro-recording", recording
    end
    local executing = vim.fn.reg_executing()
    if executing ~= "" then
      return "macro-executing", executing
    end
  end

  local ok_s, State = pcall(require, "which-key.state")
  if not (ok_s and State.state ~= nil) then
    return nil
  end

  -- THREE outcomes, not two: the window is up, the window is OBSERVED down, or
  -- the question could not be asked at all. Only an observation of absence may
  -- enter the age classifier below.
  --
  -- The first cut collapsed "could not ask" into "no window" and called that
  -- failing safe. It is the opposite: a blind instrument reported the class it
  -- cannot see as the one that gets acted on, so a `View.valid()` that raised
  -- turned every aged State into `state-orphaned` and let AUTOMATIC repair reap
  -- it without popup absence ever being established (lector, PR #18 r1, with a
  -- probe: a 30s state plus a throwing `valid()` returned
  -- `state-orphaned 30000ms with no window` — a claim about a window nobody
  -- looked at). An unobservable window is an UNKNOWN, and an unknown blocks the
  -- automatic path; the operator's forced path still clears it.
  local window ---@type boolean? nil = unobservable, true = up, false = observed down
  local ok_v, View = pcall(require, "which-key.view")
  if ok_v and type(View) == "table" and type(View.valid) == "function" then
    local ok_call, valid = pcall(View.valid)
    if ok_call then
      window = valid == true
    end
  end
  if window == true then
    return "popup-open"
  end
  if window == nil then
    return "state-live", "window validity unavailable"
  end

  local started = type(State.state) == "table" and State.state.started
  if type(started) ~= "number" then
    -- Cannot age it, so cannot call it stale. Blocks automatically; a forced
    -- repair still clears it.
    return "state-live", "unknown state shape"
  end
  local elapsed = uv.hrtime() / 1e6 - started
  if elapsed <= stale_after_ms() then
    return "state-live", ("%dms"):format(math.floor(elapsed))
  end
  return "state-orphaned", ("%dms with no window"):format(math.floor(elapsed))
end

--- True when a real interaction is in progress and an AUTOMATIC repair must
--- stand down. An orphaned State object is deliberately NOT one: it is the
--- condition the repair exists to clear.
function M.interaction_active()
  local cause = M.interaction_reason()
  return cause ~= nil and cause ~= "state-orphaned"
end

--- Clear an orphaned which-key interaction: drop the State object and take the
--- (already invalid) window down with it. Feeds no keys and touches no mapping.
---@return boolean cleared
function M.reap_state()
  local ok_s, State = pcall(require, "which-key.state")
  if not ok_s then
    return false
  end
  if State.state == nil then
    return false
  end
  -- `State.stop()` nils the field and schedules the hide; the direct assignment
  -- covers a stop() that bailed early, and the explicit hide covers the
  -- scheduled one not having run yet when the rebuild happens in this tick.
  pcall(State.stop)
  State.state = nil
  pcall(function()
    require("which-key.view").hide()
  end)
  return true
end

--- Terminate a macro recording, which is the only way to let which-key
--- re-attach its triggers while one is latched (`Triggers.schedule` refuses to
--- drain `in_macro()`).
---
--- NOTE: this is the one place the family feeds a key, and it is reachable ONLY
--- from an explicitly user-invoked repair.
---
--- REFERENCE: ADR-0091 "Amendment — 2026-09-10: operator-invoked macro
--- termination". Decision §4 as originally accepted said, unqualified, "Do not …
--- feed synthetic user keystrokes"; the amendment is what authorizes this
--- narrow exception, and it authorizes exactly this shape: never automatic, a
--- non-remapped immediate `q`, only for a VERIFIED active recording, closure
--- verified, refuse and report on failure. An earlier revision of this comment
--- claimed §4 had always been automatic-path-only — it had not, and a comment
--- is not the place to move an accepted decision (lector, PR #18 r0).
---
--- Automatic repair still may not do this under any circumstances: a recording
--- the user is building is theirs, and ending it on an idle tick would destroy
--- work silently.
--- The `x` flag is load-bearing: it drains the typeahead NOW. Without it the
--- `q` is merely queued, so `reg_recording()` is still set when this returns —
--- and the rebuild that follows in the same tick cannot stick, because
--- `Triggers.schedule` refuses to re-attach while `in_macro()`. The caller was
--- then told the recording had been closed while it was still running.
---
--- Returns what actually happened, verified by re-reading the register rather
--- than assumed from having fed the key.
---@return boolean stopped, string? register
function M.abort_macro()
  local reg = vim.fn.reg_recording()
  if reg == "" then
    return false
  end
  pcall(vim.api.nvim_feedkeys, "q", "nx", false)
  if vim.fn.reg_recording() ~= "" then
    return false, reg
  end
  return true, reg
end

return M
