-- <leader> trigger guard — detects and repairs which-key trigger loss
-- in-process (ADR-0091; spec: 2026-09-07-autovim-family-which-key-recovery).
--
-- which-key's buffer-local bare-Space `<leader>` popup trigger can be lost at
-- runtime (confirmed source defect: obsolete queued mode objects deleting
-- their replacement's trigger; plus registry/mapping desynchronization that
-- BufEnter never reconciles). With the trigger gone, every `<leader>x`
-- binding degrades to literal key replay after timeoutlen — and nothing
-- errors. Restarting Neovim was the only known recovery, which is
-- unacceptable for sessions hosting long-running terminal work.
--
-- This guard is a NET over which-key, not a change to it:
--   * It never installs any mapping of its own.
--   * It never feeds keystrokes, calls setup, or polls permanently.
--   * At safe boundaries it CHECKS the real mapping set; when the trigger
--     is genuinely missing (and nothing competes), it asks which-key to
--     rebuild that one mode via `utils.wk_compat` — the validated
--     in-place recovery core. Idempotent: a healthy trigger costs one
--     buffer-keymap scan; a repair is coalesced per event burst.
--   * It preserves user-owned mappings (never overwrites a real mapping),
--     configured disabled buffers, macros, pending operators, and an open
--     which-key popup — every case is checked before any repair.
--
-- Boundaries (per spec): BufEnter/WinEnter, return to normal mode, and
-- CursorHold (idle) — deferred and coalesced through one pending flag so a
-- burst of events produces at most one check per tick.
--
-- Manual operator recovery: `:AutovimLeaderCheck` (also `:AutovimLeaderRepair`
-- as an explicit alias) — reports and, when broken, repairs the current
-- buffer immediately, without a restart. Add `!` to force past a live
-- interaction, or use `:RepairLeaderKey` / `:lua RepairLeaderKey()`, which is
-- always forced.
--
-- THE DEADLOCK THIS ALSO HANDLES (2026-09-10). The automatic path stands down
-- during a real interaction, which is right — but two conditions were reported
-- under one name, and one of them never ends by itself:
--
--   * a latched macro RECORDING keeps `Triggers.schedule` from ever
--     re-attaching the trigger (its drain returns early while `in_macro()`),
--     so the trigger stays missing AND the guard refuses to act. Both halves
--     come from the same un-closed register — which is why closing it is the
--     first thing the forced path does, and why automation must not do it
--     (a recording in progress is the user's work). The forced path's single
--     synthetic keystroke is authorized by ADR-0091's 2026-09-10 amendment,
--     "operator-invoked macro termination", and by nothing wider.
--   * an ORPHANED `which-key.state` object — set, no window on screen, stale
--     past which-key's own timing — is not an interaction at all. The guard now
--     reaps it and proceeds, which is the case that previously produced
--     `BROKEN (which-key interaction or macro active)` on every idle tick with
--     no way out but hand-typed Lua.
--
-- Blocked repairs now name the ONE cause and what clears it, so the notice is
-- actionable instead of ambiguous.
--
-- Removability: delete this module, the plugin spec, and `utils/wk_compat`
-- together. When which-key ships a public reconciliation API the adapter is
-- the single seam to replace.

local compat = require("utils.wk_compat")

local M = {}

-- ── state ────────────────────────────────────────────────────────────────
local augroup_name = "autovim-leader-guard"
local check_pending = false
local repair_failed = false -- sticky; cleared on the next successful check

-- The leader key this guard reconciles. Resolved from the live config at
-- boundary time (not module load) so `mapleader` set later is honored.
local function leader_keys()
  local leader = vim.g.mapleader or "\\"
  if leader == "" then
    leader = "\\"
  end
  return leader
end

-- ── health predicate ─────────────────────────────────────────────────────
-- Health = the REAL buffer-local which-key trigger is present AND no stale
-- state. Registry membership alone is never trusted (the incident proved a
-- registry entry can claim presence while the actual mapping is gone).

--- Health report for the current buffer's normal-mode leader trigger.
---@return { healthy: boolean, reason: string, buf?: number }
function M.check(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return { healthy = false, reason = "no valid buffer" }
  end
  if not compat.available() then
    -- which-key not loaded (yet): nothing to guard. Fail-safe, not an error.
    return { healthy = true, reason = "which-key not loaded" }
  end
  if compat.disabled_for(buf) then
    -- which-key is configured to skip this buffer; the absence of a
    -- trigger here is correct behavior, not loss.
    return { healthy = true, reason = "disabled buffer" }
  end
  local keys = leader_keys()
  if compat.has_trigger(buf, "n", keys) then
    return { healthy = true, reason = "trigger present", buf = buf }
  end
  if compat.has_competing_mapping(buf, "n", keys) then
    -- A real mapping owns the leader — user intent; never touch it.
    return { healthy = true, reason = "competing mapping (user-owned)", buf = buf }
  end
  return { healthy = false, reason = "leader trigger missing", buf = buf }
end

-- ── repair ────────────────────────────────────────────────────────────────

-- Why a repair stood down, in words that name the ONE cause and say what
-- clears it. The old single string ("which-key interaction or macro active")
-- covered a user recording a macro and an orphaned State object alike, so the
-- warning could not tell Johno whether to press `q` or to go hunting for
-- corrupt internals — and on the orphan it repeated forever on every idle tick
-- while refusing to rebuild.
local BLOCKED_REASON = {
  ["macro-recording"] = function(detail)
    return ("macro recording (register %s) — close it with q, or :AutovimLeaderRepair! to force"):format(
      detail or "?"
    )
  end,
  ["macro-executing"] = function(detail)
    return ("macro executing (register %s) — repair resumes when the replay ends"):format(detail or "?")
  end,
  ["popup-open"] = function()
    return "which-key popup is open — repair resumes when it closes"
  end,
  ["state-live"] = function(detail)
    return ("which-key interaction starting (%s) — repair resumes when it settles"):format(detail or "in flight")
  end,
}

local function blocked_reason(cause, detail)
  local fmt = BLOCKED_REASON[cause]
  if fmt then
    return fmt(detail)
  end
  return ("which-key interaction active (%s)"):format(cause or "unknown")
end

-- Declared HERE, above every caller: as a `local function` further down the
-- file it was invisible to anything defined earlier, so a reference from
-- `M.RepairLeaderKey` would have compiled as a global read and been nil at the
-- moment the operator needed it most.
local function report_to_user(rep)
  local msg = ("[autovim] <leader> trigger: %s (%s)"):format(rep.healthy and "healthy" or "BROKEN", rep.reason)
  if rep.cleared then
    msg = msg .. " — " .. rep.cleared
  end
  vim.notify(msg, rep.healthy and vim.log.levels.INFO or vim.log.levels.WARN)
end

--- Repair the current buffer's normal-mode leader trigger in-process.
--- Returns a report; never throws.
---
--- `opts.force` is the operator's override for the case automation must not
--- take on its own: it reaps a which-key State object of ANY age and closes a
--- latched macro recording. Reachable from `:AutovimLeaderRepair!` and
--- `RepairLeaderKey()`, never from the autocmds.
---@param buf number?
---@param opts { force: boolean? }?
---@return { repaired: boolean, healthy: boolean, reason: string, cleared?: string }
function M.repair(buf, opts)
  buf = buf or vim.api.nvim_get_current_buf()
  local force = opts ~= nil and opts.force == true
  local health = M.check(buf)
  if health.healthy then
    return { repaired = false, healthy = true, reason = health.reason }
  end
  local cleared
  -- Never repair mid-interaction: macros, open popup, pending operators. The
  -- ONE exception is an orphaned State object — set, no window, and stale past
  -- which-key's own timing. That is not an interaction to protect, it is the
  -- deadlock, so it is reaped and the repair proceeds.
  if compat.available() then
    local cause, detail = compat.interaction_reason()
    if cause == "state-orphaned" then
      if compat.reap_state() then
        cleared = ("orphaned which-key state (%s)"):format(detail or "stale")
      end
    elseif cause and force then
      -- Explicit override: the macro is the load-bearing half — while a
      -- recording is latched, which-key's own `Triggers.schedule` refuses to
      -- re-attach the trigger, so rebuilding without closing it cannot stick.
      local parts = {}
      if cause == "macro-recording" then
        local stopped, reg = compat.abort_macro()
        if not stopped then
          -- Refusing here rather than rebuilding anyway: with the recording
          -- still open, `Triggers.schedule` will not re-attach, so a "repaired"
          -- report would be a claim the trigger cannot honor.
          return {
            repaired = false,
            healthy = false,
            reason = ("macro recording (register %s) would not close — press q in normal mode, then retry"):format(
              reg or "?"
            ),
          }
        end
        parts[#parts + 1] = ("macro recording (register %s)"):format(reg or "?")
      end
      if compat.reap_state() then
        parts[#parts + 1] = "which-key state"
      end
      cleared = #parts > 0 and ("forced: cleared " .. table.concat(parts, " + ")) or "forced"
    elseif cause then
      return { repaired = false, healthy = false, reason = blocked_reason(cause, detail) }
    end
  end
  if vim.api.nvim_get_mode().mode ~= "n" then
    return { repaired = false, healthy = false, reason = "not in normal mode" }
  end
  local repaired, reason = compat.rebuild_mode(buf, "n")
  -- Give the deferred trigger attach one event-loop turn, then re-check.
  if repaired then
    vim.wait(50, function()
      return M.check(buf).healthy
    end, 5)
  end
  local after = M.check(buf)
  repair_failed = not after.healthy
  if not after.healthy then
    -- `reason` is the rebuild's own account of the failure and is now
    -- trustworthy: it used to be the literal "which-key internals unavailable"
    -- on every path, because the adapter's `or false` truncated the real one
    -- (see wk_compat.rebuild_mode).
    vim.notify(
      ("[autovim] leader trigger repair failed for buffer %d: %s"):format(buf, reason or "unknown"),
      vim.log.levels.WARN
    )
  end
  return { repaired = repaired, healthy = after.healthy, reason = after.reason, cleared = cleared }
end

--- RepairLeaderKey — the one call to make when `<leader>` has gone dead.
---
--- This is the hand-typed recovery one-liner from the incident task, promoted
--- to a named entry point (Johno, 2026-09-10: "let's call the lua method
--- RepairLeaderKey for ease of memorizing"). It does what the snippet did, in
--- the same order and for the same reasons:
---
---   1. close a latched macro recording — while one is open, which-key's
---      `Triggers.schedule` will not re-attach the trigger at all, so this must
---      come first or the rebuild cannot stick;
---   2. drop the which-key State object and hide its (already invalid) window;
---   3. rebuild the current buffer's normal-mode trigger from the real mapping
---      set and report what happened.
---
--- Always forced, because it is only ever invoked BY the operator, at the
--- moment they have decided the editor is misbehaving. Reachable three ways so
--- it is findable under pressure: `:RepairLeaderKey`, `:lua RepairLeaderKey()`,
--- and `require("utils.leader_guard").RepairLeaderKey()`. All three work while
--- `<leader>` itself is dead, since none of them go through a mapping.
---@return { repaired: boolean, healthy: boolean, reason: string, cleared?: string }
function M.RepairLeaderKey()
  local rep = M.repair(nil, { force = true })
  report_to_user(rep)
  return rep
end

-- ── safe-boundary scheduling ──────────────────────────────────────────────
-- Coalesced: any number of boundary events in one tick collapse into a
-- single deferred check. The check itself is idempotent and read-only when
-- healthy.

local function schedule_check()
  if check_pending then
    return
  end
  check_pending = true
  vim.schedule(function()
    check_pending = false
    local health = M.check()
    if not health.healthy then
      M.repair()
    end
  end)
end

local function enabled()
  local v = vim.g.autovim_leader_guard
  if v == nil then
    return true
  end
  return v ~= 0 and v ~= false
end

-- ── setup ────────────────────────────────────────────────────────────────

function M.setup()
  local group = vim.api.nvim_create_augroup(augroup_name, { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "ModeChanged" }, {
    group = group,
    callback = function(ev)
      if not enabled() then
        return
      end
      -- ModeChanged: only when the NEW mode is normal mode (returning to
      -- normal is the safe boundary; leaving normal is not).
      if ev.event == "ModeChanged" and not ev.match:find("^.*:n$") then
        return
      end
      schedule_check()
    end,
  })

  -- Idle boundary: repairs a loss that happened without any window/mode
  -- transition after it (e.g. while the user paused in a popup-less state).
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = group,
    callback = function()
      if not enabled() then
        return
      end
      if vim.api.nvim_get_mode().mode ~= "n" then
        return
      end
      schedule_check()
    end,
  })

  vim.api.nvim_create_user_command("AutovimLeaderCheck", function(cmd)
    report_to_user(M.repair(nil, { force = cmd.bang }))
  end, {
    bang = true,
    desc = "Check and repair the <leader> which-key trigger without a restart (! to force)",
  })

  vim.api.nvim_create_user_command("AutovimLeaderRepair", function(cmd)
    report_to_user(M.repair(nil, { force = cmd.bang }))
  end, {
    bang = true,
    desc = "Alias of :AutovimLeaderCheck — explicit in-process leader recovery (! to force)",
  })

  -- The memorable name, as a command so it tab-completes when the operator is
  -- already annoyed. Forced by definition — see M.RepairLeaderKey.
  vim.api.nvim_create_user_command("RepairLeaderKey", function()
    M.RepairLeaderKey()
  end, {
    desc = "Force-recover the <leader> which-key trigger (macro + orphaned state + rebuild)",
  })

  -- One deliberate global, so the literal `:lua RepairLeaderKey()` Johno asked
  -- for works without remembering a module path mid-incident. Set only if
  -- nothing else owns the name.
  if rawget(_G, "RepairLeaderKey") == nil then
    _G.RepairLeaderKey = M.RepairLeaderKey
  end
end

-- Test/diagnostic surface (not used by the autocmds above).
M._state = function()
  return { check_pending = check_pending, repair_failed = repair_failed }
end

return M
