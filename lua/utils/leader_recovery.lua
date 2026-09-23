---Keep `<leader>` opening which-key, in-process, without a restart.
---
---### The failure this repairs
---
---which-key installs its leader trigger as a BUFFER-LOCAL native mapping. When
---that mapping is gone, `<leader>x` is only a PREFIX of the real mappings and
---none of them complete — so Vim waits `timeoutlen`, finds no match, and
---REPLAYS THE KEYS LITERALLY. `<leader>a` moves the cursor right and enters
---insert via `a`; `<leader>m` sets a mark; `<leader>w` writes the file. Nothing
---errors, and every letter fails differently, so it does not even look like one
---bug (Johno, 2026-09-07).
---
---Restarting Neovim is NOT an acceptable recovery: this editor hosts
---long-running terminal work, and a session may hold the only live handle on
---hours of it. See ADR-0091.
---
---### The health predicate
---
---Broken means: **longer leader bindings exist, but the native leader trigger
---does not.** That combination is unambiguous — the mappings are there to be
---reached and the thing that reaches them is missing.
---
---which-key's own registry is NOT a health signal and must never be used as
---one. During the incident it reported 13 normal-mode triggers on a buffer
---where Neovim had zero; a registry-only check calls a dead leader healthy.
---`tests/leader-recovery.lua` includes that exact substitution as a negative
---control.
---
---### Why it is only a compensation
---
---The cause is in which-key's trigger lifecycle: a retired mode object can
---destroy the live buffer's native trigger, and which-key does not notice or
---re-add it. Fixed at source on a reference branch, which is EVIDENCE ONLY —
---the shipping remedy stays family-side per ADR-0091.
---
---What this module does is narrow on purpose: detect the real predicate, then
---ask which-key to re-attach through its own lifecycle call. It reads no
---which-key private state. It is deliberately deletable: one spec entry, one
---require, one adapter.
---@module 'utils.leader_recovery'

local Adapter = require("utils.wk_adapter")

local M = {}

---@class utils.leader_recovery.State
---@field pending boolean
---@field repairs integer     repairs actually performed (test observability)
---@field checks integer      health checks run (proves coalescing)
M.stats = { pending = false, repairs = 0, checks = 0 }

---_unsafe reports why NOW is a bad moment to touch mappings, or nil when safe.
---
---Each of these is a state in which re-installing a mapping would either be
---swallowed, corrupt a recording, or interrupt the user mid-gesture.
---@return string?
local function _unsafe()
  local m = vim.fn.mode(true)
  -- Operator-pending / insert / visual / select / replace: the user is mid-input.
  if not m:match("^n") then return "mode=" .. m end
  -- `n` with a pending operator (e.g. `d` awaiting a motion) still reports "no".
  if m:match("^no") then return "operator-pending" end
  if vim.fn.reg_recording() ~= "" then return "recording-macro" end
  if vim.fn.reg_executing() ~= "" then return "executing-macro" end
  -- An open which-key popup owns the leader deliberately; repairing under it
  -- would fight the very suspension which-key is entitled to hold.
  local ok, wk = pcall(require, "which-key")
  if ok and type(wk.hide) == "function" then
    local ok_state, State = pcall(require, "which-key.state")
    if ok_state and State and State.state ~= nil then return "which-key-active" end
  end
  return nil
end

---_repairable reports whether `buf` is one this feature may touch.
---@param buf integer
---@return boolean
local function _repairable(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  -- Only real file buffers. A terminal or prompt legitimately has no leader,
  -- and which-key's own disable lists must be honoured rather than overridden.
  if vim.bo[buf].buftype ~= "" then return false end
  local ok, Config = pcall(require, "which-key.config")
  if ok and Config and Config.disable then
    if vim.tbl_contains(Config.disable.ft or {}, vim.bo[buf].filetype) then return false end
    if vim.tbl_contains(Config.disable.bt or {}, vim.bo[buf].buftype) then return false end
  end
  return true
end

---health inspects a buffer and reports whether its leader is usable.
---@param buf integer?
---@return boolean healthy
---@return string reason
function M.health(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local p = Adapter.probe()
  if not p.ok then return true, "adapter unavailable: " .. tostring(p.reason) end
  if not _repairable(buf) then return true, "buffer not in scope" end

  local leader = Adapter.leader_lhs(p.util)
  local native, user_owned = false, false
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if p.util.norm(map.lhs) == leader then
      native = true
      -- A mapping the USER owns on the leader is not which-key's to replace.
      user_owned = not (map.desc and map.desc:find("which-key", 1, true))
    end
  end
  for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
    if p.util.norm(map.lhs) == leader then native = true; user_owned = true end
  end
  if native then
    return true, user_owned and "leader mapped (user-owned)" or "leader trigger present"
  end

  -- No trigger. Only call that BROKEN when there is something to reach.
  local longer = 0
  for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
    if map.lhs:sub(1, 1) == " " and #map.lhs > 1 then longer = longer + 1 end
  end
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if map.lhs:sub(1, 1) == " " and #map.lhs > 1 then longer = longer + 1 end
  end
  if longer == 0 then return true, "no leader bindings to reach" end
  return false, ("leader trigger absent with %d longer binding(s)"):format(longer)
end

---repair restores the leader trigger for `buf`. Idempotent.
---@param buf integer?
---@param opts? { force?: boolean }   force skips the safe-moment gate
---@return boolean repaired
---@return string reason
function M.repair(buf, opts)
  buf = buf or vim.api.nvim_get_current_buf()
  opts = opts or {}
  M.stats.checks = M.stats.checks + 1

  local healthy, why = M.health(buf)
  if healthy then return false, why end

  if not opts.force then
    local unsafe = _unsafe()
    if unsafe then return false, "deferred: " .. unsafe end
  end

  local p = Adapter.probe()
  if not p.ok then return false, "adapter unavailable: " .. tostring(p.reason) end
  local mode = Adapter.mode_for(p, buf)
  if not mode then return false, "which-key has no mode for this buffer" end

  Adapter.clear_stale_suspension(p, mode)
  Adapter.attach(p, mode)

  local ok_now = M.health(buf)
  if ok_now then
    M.stats.repairs = M.stats.repairs + 1
    return true, "leader trigger restored"
  end
  return false, "attach did not restore the trigger"
end

---_schedule coalesces bursts. Buffer/window events arrive in clusters (a split
---fires several at once), and a check per event would be pure waste.
local function _schedule()
  if M.stats.pending then return end
  M.stats.pending = true
  vim.defer_fn(function()
    M.stats.pending = false
    pcall(M.repair)
  end, 50)
end

---setup installs the safe-boundary checks. Idempotent.
function M.setup()
  local group = vim.api.nvim_create_augroup("AutovimLeaderRecovery", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "RecordingLeave" }, {
    group = group,
    callback = _schedule,
    desc = "Restore <leader> -> which-key if its native trigger went missing",
  })
  vim.api.nvim_create_user_command("AutovimLeaderRecover", function()
    local ok, why = M.repair(nil, { force = true })
    vim.notify(
      ok and ("leader recovery: " .. why) or ("leader recovery: no action — " .. why),
      ok and vim.log.levels.INFO or vim.log.levels.WARN
    )
  end, { desc = "Repair <leader> -> which-key in this buffer without restarting" })
end

return M
