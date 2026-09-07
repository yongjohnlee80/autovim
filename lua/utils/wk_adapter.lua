---Narrow, feature-detected access to which-key internals.
---
---EVERY dependency-internal reach in the leader-recovery feature goes through
---this file, so the coupling has exactly one home and one place to delete when
---which-key ships a public reconciliation contract (ADR-0091).
---
---### What this adapter needs, and why
---
---which-key's module lifecycle functions (`buf.get`, `triggers.attach`,
---`util.norm`) plus ONE private table: `which-key.triggers.suspended`.
---
---Two distinct broken states exist, and they need different remedies:
---
---  (i)  native trigger destroyed, mode NOT suspended
---         -> `attach()` alone reinstalls it.
---  (ii) native trigger destroyed AND the mode left SUSPENDED
---         -> `attach()` returns early FOREVER. Measured: mode suspended,
---            trigger tree intact at 12 entries, `attach` a no-op; clearing the
---            suspension then attaching restores it.
---
---State (ii) is reachable through ordinary use: which-key suspends a mode while
---a macro RECORDS, and the suspension can outlive the recording.
---
---This was nearly got wrong in both directions. A first draft cleared the
---suspension without a test that observed it — mutation showed removing the
---clear changed nothing, because the fixture produced state (i) and `Buf.get()`
---returned a different, non-suspended mode. The clear was then removed as
---decoration, and a macro-recording test immediately proved it necessary. The
---lesson is in the suite: section [5b] drives the non-forced path across a real
---`q`-recording, which is the only fixture that reaches state (ii).
---
---### Failure policy: safe AND loud
---
---A future which-key that moves these functions must not silently return the
---leader to dying. `probe()` reports an actionable incompatibility naming the
---missing symbol; the recovery refuses rather than pretending, and the suite
---asserts the probe fails when a required function is absent.
---@module 'utils.wk_adapter'

local M = {}

---@class utils.wk_adapter.Probe
---@field ok boolean
---@field reason string?          why the adapter cannot operate
---@field triggers table?         which-key.triggers
---@field buf table?              which-key.buf
---@field util table?             which-key.util

---probe resolves which-key's internals and reports whether this adapter can
---still operate against the installed version.
---@return utils.wk_adapter.Probe
function M.probe()
  local ok_t, Triggers = pcall(require, "which-key.triggers")
  if not ok_t or type(Triggers) ~= "table" then
    return { ok = false, reason = "which-key.triggers is not loadable" }
  end
  local ok_b, Buf = pcall(require, "which-key.buf")
  if not ok_b or type(Buf) ~= "table" or type(Buf.get) ~= "function" then
    return { ok = false, reason = "which-key.buf.get is missing" }
  end
  local ok_u, Util = pcall(require, "which-key.util")
  if not ok_u or type(Util) ~= "table" or type(Util.norm) ~= "function" then
    return { ok = false, reason = "which-key.util.norm is missing" }
  end
  if type(Triggers.attach) ~= "function" then
    return { ok = false, reason = "which-key.triggers.attach is missing" }
  end
  -- The one private-state dependency, and it is load-bearing: see the header.
  if type(Triggers.suspended) ~= "table" then
    return {
      ok = false,
      reason = "which-key.triggers.suspended is no longer a table — a stale suspension "
        .. "can no longer be cleared, so a leader lost after macro recording would stay "
        .. "lost; re-verify ADR-0091 against this which-key version",
    }
  end
  return { ok = true, triggers = Triggers, buf = Buf, util = Util }
end

---leader_lhs is the normalised form of `<leader>` for map comparisons.
---@param util table
---@return string
function M.leader_lhs(util)
  return util.norm("<leader>")
end

---mode_for returns which-key's CURRENT normal-mode object for `buf`, or nil.
---@param p utils.wk_adapter.Probe
---@param buf integer
---@return table?
function M.mode_for(p, buf)
  local ok, mode = pcall(p.buf.get, { buf = buf, mode = "n" })
  if not ok then return nil end
  return mode
end

---clear_stale_suspension drops a suspension left behind for `mode`.
---
---which-key suspends a mode to step out of the way — notably while a macro
---RECORDS. When the suspension outlives its cause, `Triggers.attach` returns
---early forever and the mode's trigger tree stays intact but uninstalled.
---
---Returns whether a suspension was actually present, so the caller can report a
---no-op honestly rather than claim a repair it did not perform.
---@param p utils.wk_adapter.Probe
---@param mode table
---@return boolean cleared
function M.clear_stale_suspension(p, mode)
  if p.triggers.suspended[mode] == nil then return false end
  p.triggers.suspended[mode] = nil
  return true
end

---attach asks which-key to re-install the mode's triggers.
---@param p utils.wk_adapter.Probe
---@param mode table
---@return boolean ok
function M.attach(p, mode)
  return (pcall(p.triggers.attach, mode))
end

return M
