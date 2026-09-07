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
-- buffer immediately, without a restart.
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

--- Repair the current buffer's normal-mode leader trigger in-process.
--- Returns a report; never throws.
---@return { repaired: boolean, healthy: boolean, reason: string }
function M.repair(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local health = M.check(buf)
  if health.healthy then
    return { repaired = false, healthy = true, reason = health.reason }
  end
  -- Never repair mid-interaction: macros, open popup, pending operators.
  if compat.available() and compat.interaction_active() then
    return { repaired = false, healthy = false, reason = "which-key interaction or macro active" }
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
    vim.notify(
      ("[autovim] leader trigger repair failed for buffer %d: %s"):format(buf, reason or "unknown"),
      vim.log.levels.WARN
    )
  end
  return { repaired = repaired, healthy = after.healthy, reason = after.reason }
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

-- ── commands ──────────────────────────────────────────────────────────────

local function report_to_user(rep)
  local msg = ("[autovim] <leader> trigger: %s (%s)"):format(rep.healthy and "healthy" or "BROKEN", rep.reason)
  vim.notify(msg, rep.healthy and vim.log.levels.INFO or vim.log.levels.WARN)
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

  vim.api.nvim_create_user_command("AutovimLeaderCheck", function()
    local rep = M.repair()
    report_to_user(rep)
  end, {
    desc = "Check and repair the <leader> which-key trigger without a restart",
  })

  vim.api.nvim_create_user_command("AutovimLeaderRepair", function()
    local rep = M.repair()
    report_to_user(rep)
  end, {
    desc = "Alias of :AutovimLeaderCheck — explicit in-process leader recovery",
  })
end

-- Test/diagnostic surface (not used by the autocmds above).
M._state = function()
  return { check_pending = check_pending, repair_failed = repair_failed }
end

return M
