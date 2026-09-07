-- tests/leader-recovery.lua — ADR-0091 family-side leader recovery.
--
-- Drives the REAL defect against the STOCK pinned which-key (no fork), proves
-- the fixture is genuinely broken before repairing it, and includes negative
-- controls that fail when the hook is removed or the health predicate is
-- swapped for which-key's internal registry.
local root = vim.fn.fnamemodify(
  vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h:h"), ":p")

-- Sandbox every XDG root BEFORE any plugin loads. A suite that writes into the
-- developer's real config is the defect this family already shipped once.
local sandbox = vim.fn.tempname() .. "-leader-recovery"
vim.env.XDG_CONFIG_HOME = sandbox .. "/config"
vim.env.XDG_DATA_HOME   = sandbox .. "/data"
vim.env.XDG_STATE_HOME  = sandbox .. "/state"
vim.env.XDG_CACHE_HOME  = sandbox .. "/cache"

vim.g.mapleader = " "
vim.o.timeout, vim.o.timeoutlen = true, 300

local WK = vim.fn.expand("~/.local/share/nvim/lazy/which-key.nvim")
vim.opt.rtp:prepend(WK)
local SN = vim.fn.expand("~/.local/share/nvim/lazy/snacks.nvim")
if vim.fn.isdirectory(SN) == 1 then vim.opt.rtp:prepend(SN) end
vim.opt.rtp:prepend(root)
package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local pass, fail = 0, 0
local function ok(n, c, d)
  if c then pass = pass + 1; io.stdout:write("  PASS  " .. n .. "\n")
  else fail = fail + 1
    io.stdout:write("  FAIL  " .. n .. (d and ("  — " .. tostring(d)) or "") .. "\n") end
  io.stdout:flush()
end

io.stdout:write("ADR-0091 — family-side leader recovery\n")

-- PROVENANCE. Without this the suite could be measuring a sibling worktree, the
-- reference which-key fork, or the developer's live config and never say so.
io.stdout:write("\n[0] provenance and isolation\n")
ok("XDG config is sandboxed", vim.startswith(vim.fn.stdpath("config"), sandbox),
  vim.fn.stdpath("config"))
ok("XDG state is sandboxed", vim.startswith(vim.fn.stdpath("state"), sandbox),
  vim.fn.stdpath("state"))
-- `source:sub(2)`, not `short_src`: short_src ABBREVIATES long paths with
-- "...", so a prefix comparison against it silently fails on exactly the deep
-- worktree paths this repo uses.
local function src_of(fn) return (debug.getinfo(fn, "S").source or ""):sub(2) end
local wk_src = src_of(require("which-key.triggers").attach)
ok("which-key loaded from the INSTALLED pin, not the reference fork",
  wk_src:find("lazy/which-key.nvim", 1, true) ~= nil
    and wk_src:find("trigger%-lifecycle") == nil, wk_src)
local lr_src = src_of(require("utils.leader_recovery").health)
ok("leader_recovery loaded from THIS worktree",
  lr_src:find("autovim/leader%-lifecycle") ~= nil, lr_src)

local LR = require("utils.leader_recovery")
local Adapter = require("utils.wk_adapter")
require("which-key").setup({})
vim.keymap.set("n", "<leader>ac", function() end, { desc = "child ac" })

local Buf = require("which-key.buf")
local Triggers = require("which-key.triggers")
local Util = require("which-key.util")
local function native(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if Util.norm(m.lhs) == Util.norm("<leader>") then return true end
  end
  return false
end

-- A real file buffer; the feature deliberately ignores nofile/terminal.
local tmp = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "local a = 1", "local b = 2" }, tmp)
vim.cmd.edit(vim.fn.fnameescape(tmp))
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
vim.wait(300)

io.stdout:write("\n[1] adapter\n")
local p = Adapter.probe()
ok("adapter probes the installed which-key successfully", p.ok, p.reason)

io.stdout:write("\n[2] healthy baseline\n")
ok("native leader trigger present", native())
local h, why = LR.health()
ok("health() reports healthy", h == true, why)

io.stdout:write("\n[3] the fixture is GENUINELY broken before repair\n")
-- Reproduce the real mechanism: a retired mode object detaches, destroying the
-- live trigger, and leaves a suspension that makes attach a permanent no-op.
local gen1 = Buf.get({ buf = 0, mode = "n" })
Buf.clear()
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 }); vim.wait(200)
Triggers.detach(gen1)
ok("*** native leader trigger is GONE ***", native() == false)
local longer = 0
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if m.lhs:sub(1, 1) == " " and #m.lhs > 1 then longer = longer + 1 end
end
ok("longer leader bindings still exist (the real predicate)", longer > 0, longer)
local h2, why2 = LR.health()
ok("health() reports BROKEN", h2 == false, why2)
-- The literal-replay symptom, measured rather than described.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(" a", true, false, true), "x", false)
vim.wait(400); vim.api.nvim_feedkeys("", "x", false)
ok("broken leader replays literally (cursor moved)",
  vim.api.nvim_win_get_cursor(0)[2] > 0, vim.api.nvim_win_get_cursor(0)[2])
vim.cmd("stopinsert")

io.stdout:write("\n[4] recovery, in the same process\n")
local repaired, rwhy = LR.repair(nil, { force = true })
ok("*** repair() restores the trigger ***", repaired == true, rwhy)
ok("native leader trigger is back", native() == true)
ok("health() reports healthy again", (LR.health()) == true)

-- A child action must run EXACTLY once — not zero (dead) and not twice (a
-- doubled mapping would also "look" restored).
local fired = 0
vim.keymap.set("n", "<leader>zz", function() fired = fired + 1 end, { desc = "probe" })
LR.repair(nil, { force = true })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(" zz", true, false, true), "x", false)
vim.wait(200)
ok("a child action fires exactly once after recovery", fired == 1, fired)

io.stdout:write("\n[5] idempotence and coalescing\n")
local before = LR.stats.repairs
LR.repair(nil, { force = true }); LR.repair(nil, { force = true })
ok("repairing a healthy buffer performs no repair", LR.stats.repairs == before,
  ("%d -> %d"):format(before, LR.stats.repairs))

io.stdout:write("\n[5b] the safe-moment gate (non-forced path)\n")
-- Everything above uses force=true, which BYPASSES the gate — so without this
-- section the gate is unobserved and deleting it leaves the suite green
-- (verified by mutation). The spec requires macro/operator/insert safety, so it
-- gets a cell that exercises the real automatic path.
vim.cmd.edit(vim.fn.fnameescape(tmp))
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 }); vim.wait(200)
local g5 = Buf.get({ buf = 0, mode = "n" })
Buf.clear()
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 }); vim.wait(200)
Triggers.detach(g5)
ok("5b: trigger broken again for the gate test", native() == false)

vim.cmd("normal! qq")                       -- start recording into register q
ok("5b: recording is active", vim.fn.reg_recording() ~= "")
local gated, gwhy = LR.repair()             -- NO force: the automatic path
ok("5b: *** repair DEFERS while a macro records ***", gated == false, gwhy)
ok("5b: ...and says why", (gwhy or ""):find("recording", 1, true) ~= nil, gwhy)
ok("5b: the trigger is still absent (it really did nothing)", native() == false)
vim.cmd("normal! q")                        -- stop recording
ok("5b: recording stopped", vim.fn.reg_recording() == "")

local ungated, uwhy = LR.repair()           -- still no force
ok("5b: *** repair proceeds once the moment is safe ***", ungated == true, uwhy)
ok("5b: trigger restored via the non-forced path", native() == true)

io.stdout:write("\n[6] preservation\n")
ok("longer leader bindings survived recovery", (function()
  local n = 0
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    if m.lhs:sub(1, 1) == " " and #m.lhs > 1 then n = n + 1 end
  end
  return n >= longer
end)(), "longer bindings lost")

-- A user-owned leader mapping is not which-key's to replace, and must not be
-- reported broken or overwritten.
vim.keymap.set("n", "<leader>", function() end, { desc = "USER OWNED leader" })
local hu, whyu = LR.health()
ok("a user-owned <leader> mapping reads healthy", hu == true, whyu)
ok("...and is described as user-owned", (whyu or ""):find("user%-owned") ~= nil, whyu)
pcall(vim.keymap.del, "n", "<leader>")

io.stdout:write("\n[7] out-of-scope buffers are left alone\n")
vim.cmd("enew")
vim.bo.buftype = "nofile"
ok("a nofile buffer reads healthy (not in scope)", (LR.health()) == true)

io.stdout:write("\n[8] NEGATIVE CONTROLS\n")
-- N1: the health predicate must NOT be satisfiable by which-key's registry.
-- Registry-only bookkeeping reported 13 triggers on a buffer with zero native
-- maps during the incident; a predicate built on it calls a dead leader healthy.
vim.cmd.edit(vim.fn.fnameescape(tmp))
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 }); vim.wait(200)
local g2 = Buf.get({ buf = 0, mode = "n" })
Buf.clear()
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 }); vim.wait(200)
Triggers.detach(g2)
local registry_count = 0
for _, t in pairs(Triggers._triggers or {}) do
  if t.buf == vim.api.nvim_get_current_buf() then registry_count = registry_count + 1 end
end
local real_health = LR.health()
ok("N1: registry-only bookkeeping would MISS this outage",
  real_health == false, ("registry=%d realhealth=%s"):format(registry_count, tostring(real_health)))

-- N2: an adapter that cannot see `suspended` must refuse, loudly, not silently.
local saved = Triggers.attach
Triggers.attach = nil
local probe_broken = Adapter.probe()
ok("N2: adapter refuses when a required which-key function is gone",
  probe_broken.ok == false)
ok("N2: ...and names the symbol that broke",
  (probe_broken.reason or ""):find("attach", 1, true) ~= nil, probe_broken.reason)
local rep_ok, rep_why = LR.repair(nil, { force = true })
ok("N2: repair refuses rather than pretending", rep_ok == false, rep_why)
Triggers.attach = saved

-- N3: with the adapter restored, the same buffer repairs — proving N2 measured
-- the adapter and not a buffer that had become unrepairable.
ok("N3: repair works again once the adapter is restored",
  (LR.repair(nil, { force = true })) == true)

io.stdout:write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail > 0 and 1 or 0)
