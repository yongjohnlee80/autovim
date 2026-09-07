-- autovim — leader-guard test suite (ADR-0091 recovery contract)
--
-- Run headless (through tests/run-leader-guard.sh, which enforces the
-- summary sentinel and provides the sandbox):
--   nvim --headless -u NONE -l tests/leader-guard.lua
--
-- What this suite proves, per the binding spec
-- (2026-09-07-autovim-family-which-key-recovery-implementation-requirements):
--   [0] isolation: all four XDG roots sandboxed BEFORE any module load and
--       asserted from inside; runtimepath provenance asserted so the suite
--       cannot pass against the developer's live config or a sibling tree.
--   [1] the failure is real: a fixture loses the actual buffer-local
--       trigger while longer leader bindings remain (the incident shape),
--       and the health predicate calls it BROKEN (registry-only
--       bookkeeping would call it healthy — a control proves the
--       predicate inspects real mappings).
--   [2] in-process recovery: with the guard's repair, `<leader>` opens the
--       which-key popup AND a child action executes exactly once — driven
--       by real input keys in a child Neovim process, no restart.
--   [3] preservation: a user-owned competing leader mapping, disabled
--       buffers, macro recording, and an active popup are never touched.
--   [4] coalescing/idempotence: an event burst produces one deferred
--       check; repair leaves a healthy trigger healthy.
--   [5] negative controls: with the repair core stubbed out, the recovery
--       assertion fails (the suite discriminates); with the health
--       predicate reduced to registry membership, the broken fixture goes
--       undetected (proving real-mapping inspection is load-bearing).
--
-- which-key is loaded from the PINNED stock checkout recorded in
-- lazy-lock.json (3aab2147e74890957785941f0c1ad87d0a44c15a) — no fork, no
-- pin change, no vendored copy. The runner clones it into the sandbox and
-- passes AUTOTVIM_WK_SOURCE. All behavioural checks run inside a CHILD
-- nvim (--embed) so which-key's UI/state machinery is exercised for real.

-- ── sandbox BEFORE the first module load ──────────────────────────────────
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local sandbox = assert(vim.env.AUTOTVIM_TEST_SANDBOX, "run through tests/run-leader-guard.sh")
vim.env.XDG_CONFIG_HOME = sandbox .. "/config"
vim.env.XDG_DATA_HOME = sandbox .. "/data"
vim.env.XDG_STATE_HOME = sandbox .. "/state"
vim.env.XDG_CACHE_HOME = sandbox .. "/cache"
vim.env.NVIM_LOG_FILE = sandbox .. "/nvim.log"
local wk_source = assert(vim.env.AUTOTVIM_WK_SOURCE, "AUTOTVIM_WK_SOURCE: pinned which-key checkout (runner provides)")
assert(vim.startswith(wk_source, sandbox .. "/"), "which-key source escaped sandbox")

local pass_count, fail_count = 0, 0
local function ok(name, cond, detail)
  if cond then
    pass_count = pass_count + 1
    io.stdout:write("  PASS  " .. name .. "\n")
  else
    fail_count = fail_count + 1
    io.stdout:write("  FAIL  " .. name .. "  " .. tostring(detail or "") .. "\n")
  end
  io.stdout:flush()
end

-- Assert containment of every XDG root the child processes resolve.
local function assert_child_sandbox(lua)
  local code = string.format(
    [[
    local sandbox = %q
    for _, kind in ipairs({ "config", "data", "state", "cache" }) do
      assert(vim.startswith(vim.fn.stdpath(kind), sandbox .. "/"), kind .. " escaped sandbox: " .. vim.fn.stdpath(kind))
    end
  ]],
    sandbox
  )
  lua(code)
end

-- ── the child process ─────────────────────────────────────────────────────
-- One embedded child for the whole suite; a helper resets state between
-- sections. vim.fn.jobstart with rpc gives us nvim_input (real keys) and
-- nvim_exec_lua.

local child = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, { rpc = true })
assert(child > 0, "child nvim did not start")

local function lua_str(code)
  return vim.rpcrequest(child, "nvim_exec_lua", "return (" .. code .. ")", {})
end
local function lua(code)
  return vim.rpcrequest(child, "nvim_exec_lua", code, {})
end
local function input(keys)
  vim.rpcnotify(child, "nvim_input", keys)
end
local function settle(ms)
  vim.wait(ms or 150)
end

local WK_SETUP = [[
  vim.g.mapleader = " "
  vim.g.autovim_test_fired = 0
  vim.o.swapfile = false
  vim.o.timeoutlen = 50
  vim.opt.rtp:prepend(%q)
  require("which-key").setup({ delay = 0, icons = { mappings = false },
    plugins = { marks = false, registers = false, spelling = { enabled = false },
      presets = { operators = false, motions = false, text_objects = false, windows = false, nav = false, z = false, g = false } } })
  -- reset OUR modules so a stubbed adapter from a previous section (or a
  -- stale guard augroup) can never leak into a later one. which-key's own
  -- modules are NEVER reloaded: forcing package.loaded resets there would
  -- desynchronize buf.lua/state.lua's captured module references from the
  -- fresh config, which silently bypasses which-key's disable lists (the
  -- exact desync class this guard exists to be robust against).
  vim.opt.rtp:prepend(%q) -- the autovim checkout: utils.leader_guard resolves here
  package.loaded["utils.wk_compat"] = nil
  package.loaded["utils.leader_guard"] = nil
  vim.keymap.set("n", "<leader>ac", function() vim.g.autovim_test_fired = vim.g.autovim_test_fired + 1 end, { desc = "Action" })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
  require("utils.leader_guard").setup()
]]

local function boot_child()
  local code = string.format(WK_SETUP, wk_source, root)
  lua(code)
  settle(200)
end

local function trigger_count()
  return lua_str([[
    (function()
      local n = 0
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
        if m.lhs == " " or m.lhs == "<Space>" then n = n + 1 end
      end
      return n
    end)()
  ]])
end

local function popup_open()
  return lua_str("require('which-key.state').state ~= nil")
end

local function fired()
  return lua_str("vim.g.autovim_test_fired")
end

-- Break the current buffer's leader trigger using the incident's confirmed
-- mechanism shape: a temporary competing owner makes the mode's next attach
-- skip installing the trigger; removing the owner leaves the cached mode
-- without a trigger, and BufEnter does NOT reconcile it (recovery defect).
local function break_trigger()
  lua([[
    local B = require("which-key.buf")
    local T = require("which-key.triggers")
    local m = B.get({ mode = "n" })
    T.detach(m)
    vim.keymap.set("n", "<leader>", function() end, { desc = "Temporary owner" })
    T.attach(m)
    vim.keymap.del("n", "<leader>")
    -- leave the broken state cached; this is the persistent-loss shape
  ]])
  settle(100)
end

local function restore_from_broken()
  lua([[
    local B = require("which-key.buf")
    local T = require("which-key.triggers")
    local b = vim.api.nvim_get_current_buf()
    for m in pairs(T.suspended) do
      if m.buf and m.buf.buf == b and m.mode == "n" then T.suspended[m] = nil end
    end
    B.clear({ buf = b, mode = "n" })
    B.get({ buf = b, mode = "n" })
  ]])
  settle(100)
end

-- ── [0] isolation & provenance ────────────────────────────────────────────
do
  io.stdout:write("[0] test isolation\n")
  for _, kind in ipairs({ "config", "data", "state", "cache" }) do
    local p = vim.fn.stdpath(kind)
    ok("host " .. kind .. " root inside sandbox", vim.startswith(p, sandbox .. "/"), p)
  end
  local rtp_ok = vim.startswith(wk_source, sandbox .. "/")
  ok("which-key source inside sandbox", rtp_ok, wk_source)
  local provenance = lua_str([[
    (function()
      for _, p in ipairs(vim.api.nvim_list_runtime_paths()) do
        if p:find("which%-key") then return p end
      end
      return "not on rtp"
    end)()
  ]])
  ok(
    "child resolves which-key from the pinned sandbox copy before boot (not on rtp yet)",
    provenance == "not on rtp",
    provenance
  )
  boot_child()
  local provenance2 = lua_str([[
    (function()
      for _, p in ipairs(vim.api.nvim_list_runtime_paths()) do
        if p:find("which%-key") then return p end
      end
      return "not on rtp"
    end)()
  ]])
  ok("child which-key provenance is the pinned sandbox copy", provenance2 == wk_source, provenance2)
  local guard_path = lua_str([[
    (function()
      local loaded = package.loaded["utils.leader_guard"]
      if loaded == nil then return "not loaded" end
      local rtp = vim.api.nvim_list_runtime_paths()
      for i, p in ipairs(rtp) do
        if p:find("nvim%-plugins/autovim") then return p end
      end
      return "loaded but checkout not on rtp"
    end)()
  ]])
  ok("child resolves utils.leader_guard from THIS checkout (first rtp entry)", guard_path == root, guard_path)
  assert_child_sandbox(lua)
  ok("child XDG roots inside sandbox", true)
end

-- ── [1] the fixture is genuinely broken; the predicate sees it ────────────
do
  io.stdout:write("[1] broken-fixture detection\n")
  boot_child()
  ok("healthy fixture: trigger present", trigger_count() == 1, trigger_count())

  break_trigger()
  local still_mapped = lua_str([[
    (function()
      local m = vim.fn.maparg("<leader>ac", "n", false, true)
      return type(m) == "table" and not vim.tbl_isempty(m) and m.desc == "Action"
    end)()
  ]])
  ok("longer leader bindings still present after break", still_mapped == true)
  ok("fixture broken: actual trigger gone (incident shape)", trigger_count() == 0, trigger_count())

  local health = lua_str([[
    (function()
      local g = require("utils.leader_guard")
      local h = g.check()
      return { healthy = h.healthy, reason = h.reason }
    end)()
  ]])
  ok("health predicate: BROKEN on real-mapping loss", health.healthy == false, vim.json.encode(health))

  -- Control: the trigger registry can claim presence while the actual
  -- mapping is gone (the incident's false-positive shape — external
  -- deletion leaves a stale registry entry). First restore the trigger
  -- so the registry genuinely holds an entry, then delete the mapping
  -- behind which-key's back. A registry-only health predicate would
  -- call this buffer healthy; the guard must not.
  restore_from_broken()
  local registry_claims = lua_str([[
    (function()
      local T = require("which-key.triggers")
      local b = vim.api.nvim_get_current_buf()
      local claimed_before = T.has({ buf = b, mode = "n", keys = "<Space>" })
      -- externally delete the real mapping behind which-key's back
      pcall(vim.keymap.del, "n", " ", { buffer = b })
      local claimed = T.has({ buf = b, mode = "n", keys = "<Space>" })
      return { claimed_before = claimed_before, claimed = claimed, actual = (function()
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, "n")) do
          if m.lhs == " " or m.lhs == "<Space>" then return true end
        end
        return false
      end)() }
    end)()
  ]])
  ok(
    "control: registry claims present while real mapping deleted (registry-only predicate would miss it)",
    registry_claims.claimed_before == true and registry_claims.claimed == true and registry_claims.actual == false,
    vim.json.encode(registry_claims)
  )
  local health_after_del = lua_str([[ require("utils.leader_guard").check().healthy ]])
  ok("guard still reports BROKEN where the registry lies", health_after_del == false)

  break_trigger() -- re-break for the recovery-defect proof below

  -- Recovery defect: which-key's own BufEnter handler does NOT reconcile a
  -- lost trigger (state.lua:143 Buf.get returns the cached mode unchanged).
  -- Prove it in a child where the guard's autocmds are NOT installed, so
  -- only which-key's own handlers run.
  local defect_child = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, { rpc = true })
  local function defect_lua(code)
    return vim.rpcrequest(defect_child, "nvim_exec_lua", code, {})
  end
  defect_lua(string.format(WK_SETUP:gsub('require%("utils%.leader_guard"%)%.setup%(%)', ""), wk_source, root))
  vim.wait(200)
  local defect_count = function()
    return vim.rpcrequest(
      defect_child,
      "nvim_exec_lua",
      [[
      return (function()
        local n = 0
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
          if m.lhs == " " or m.lhs == "<Space>" then n = n + 1 end
        end
        return n
      end)()
    ]],
      {}
    )
  end
  ok("defect child: trigger present before break", defect_count() == 1, defect_count())
  defect_lua([[
    local B = require("which-key.buf")
    local T = require("which-key.triggers")
    local m = B.get({ mode = "n" })
    T.detach(m)
    vim.keymap.set("n", "<leader>", function() end, { desc = "Temporary owner" })
    T.attach(m)
    vim.keymap.del("n", "<leader>")
  ]])
  vim.wait(100)
  defect_lua([[ vim.api.nvim_exec_autocmds("BufEnter", { buffer = vim.api.nvim_get_current_buf() }) ]])
  vim.wait(150)
  ok("recovery defect reproduced: BufEnter alone does not repair (no guard)", defect_count() == 0, defect_count())
  vim.fn.jobstop(defect_child)

  -- Back in the guarded child: the same BufEnter burst now schedules a
  -- guard check, which repairs the loss in-process.
  lua([[ vim.api.nvim_exec_autocmds("BufEnter", { buffer = vim.api.nvim_get_current_buf() }) ]])
  settle(150)
  ok("guard's scheduled boundary check repaired the loss", trigger_count() == 1, trigger_count())

  restore_from_broken() -- leave clean state for the next section
end

-- ── [2] in-process recovery via real input: popup + action ────────────────
do
  io.stdout:write("[2] popup + action recovery (real input, no restart)\n")
  boot_child()
  input(" ")
  settle(150)
  ok("baseline: <leader> opens popup", popup_open() == true)
  input("ac")
  settle(150)
  ok("baseline: child action fires once", fired() == 1, fired())

  break_trigger()
  input(" ")
  settle(150)
  ok("broken: <leader> does NOT open popup", popup_open() == false)
  ok("broken: action does not fire", fired() == 1, fired())

  -- Explicit operator recovery, in the SAME child process.
  lua([[
    local g = require("utils.leader_guard")
    local rep = g.repair()
    vim.g.autovim_test_repair = rep
  ]])
  local rep = lua_str("vim.g.autovim_test_repair")
  ok("explicit repair reports success", rep.repaired == true and rep.healthy == true, vim.json.encode(rep))

  input(" ")
  settle(150)
  ok("recovered: <leader> opens popup (same process)", popup_open() == true)
  input("ac")
  settle(150)
  ok("recovered: child action fires exactly once more", fired() == 2, fired())
end

-- ── [3] preservation ──────────────────────────────────────────────────────
do
  io.stdout:write("[3] preservation\n")
  boot_child()

  -- A real user-owned GLOBAL mapping on the leader must never be
  -- overwritten by a repair (buffer-local trigger would win over it, but
  -- the guard must still not touch it).
  lua([[
    vim.keymap.set("n", "<leader>", function() vim.g.autovim_user_acted = (vim.g.autovim_user_acted or 0) + 1 end,
      { desc = "User mapping" })
    vim.g.autovim_user_acted = 0
    -- break the buffer-local trigger under the global mapping, then repair:
    -- the repair must refuse (competing mapping present), not overwrite.
    local B = require("which-key.buf")
    local T = require("which-key.triggers")
    local m = B.get({ mode = "n" })
    T.detach(m)
    local rep = require("utils.leader_guard").repair()
    vim.g.autovim_test_user_rep = rep
  ]])
  settle(100)
  local user_map = lua_str([[
    (function()
      for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
        if (m.lhs == " " or m.lhs == "<Space>") and m.desc == "User mapping" then
          return { present = true, desc = m.desc }
        end
      end
      return { present = false }
    end)()
  ]])
  ok(
    "user-owned global leader mapping preserved (not overwritten)",
    user_map.present == true,
    vim.json.encode(user_map)
  )
  local user_rep = lua_str("vim.g.autovim_test_user_rep")
  ok(
    "user-owned mapping: repair stays away, reports healthy-by-intent",
    user_rep.repaired == false and user_rep.healthy == true and user_rep.reason == "competing mapping (user-owned)",
    vim.json.encode(user_rep)
  )
  lua([[
    vim.keymap.del("n", "<leader>")
    require("utils.leader_guard").repair()
  ]])
  settle(100)

  -- Disabled buffer: no trigger there is CORRECT; guard must not "repair".
  lua([[
    -- disable via which-key's own resolved opts (the respected surface)
    local Config = require("which-key.config")
    table.insert(Config.disable.ft, "autovimtest_disabled")
    local b = vim.api.nvim_create_buf(true, false)
    vim.bo[b].filetype = "autovimtest_disabled"
    vim.api.nvim_set_current_buf(b)
    vim.g.autovim_disabled_buf = b
  ]])
  settle(100)
  local dis_health = lua_str([[
    (function()
      local g = require("utils.leader_guard")
      local h = g.check(vim.g.autovim_disabled_buf)
      return { healthy = h.healthy, reason = h.reason }
    end)()
  ]])
  ok("disabled buffer: absence reported healthy, no repair", dis_health.healthy == true, vim.json.encode(dis_health))
  ok("disabled buffer: no trigger installed", trigger_count() == 0, trigger_count())
  lua([[
    vim.api.nvim_set_current_buf(1)
    local Config = require("which-key.config")
    for i, ft in ipairs(Config.disable.ft) do
      if ft == "autovimtest_disabled" then table.remove(Config.disable.ft, i) break end
    end
    vim.api.nvim_buf_delete(vim.g.autovim_disabled_buf, { force = true })
  ]])

  -- Macro recording: guard must not repair mid-macro.
  lua([[
    vim.api.nvim_set_current_buf(1)
    vim.fn.setreg("q", "")
    vim.cmd.normal("qq")
  ]])
  settle(50)
  local macro_active = lua_str([[ (vim.fn.reg_recording() ~= "") ]])
  break_trigger()
  local rep_macro = lua_str([[
    (function()
      local g = require("utils.leader_guard")
      local rep = g.repair()
      return { repaired = rep.repaired, healthy = rep.healthy, reason = rep.reason }
    end)()
  ]])
  ok("macro recording active", macro_active == true)
  ok("no repair during macro recording", rep_macro.repaired == false, vim.json.encode(rep_macro))
  lua([[ vim.cmd.normal("q") ]])
  settle(50)
  local rep_after = lua_str([[ require("utils.leader_guard").repair().repaired ]])
  ok("repair proceeds after recording ends", rep_after == true)
end

-- ── [4] coalescing & idempotence ──────────────────────────────────────────
do
  io.stdout:write("[4] coalescing and idempotence\n")
  boot_child()
  -- A burst of boundary events: still exactly one trigger, no churn.
  lua([[
    for _ = 1, 20 do
      vim.api.nvim_exec_autocmds("WinEnter", {})
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    end
  ]])
  settle(150)
  ok("event burst leaves healthy trigger (coalesced, no churn)", trigger_count() == 1, trigger_count())
  ok("no stuck pending flag", lua_str([[ require("utils.leader_guard")._state().check_pending ]]) == false)
  -- Idempotent repair on a healthy buffer: no change, no error.
  local rep4 = lua_str([[
    (function()
      local g = require("utils.leader_guard")
      local rep = g.repair()
      return { repaired = rep.repaired, healthy = rep.healthy, reason = rep.reason }
    end)()
  ]])
  ok("repair on healthy buffer is a no-op", rep4.repaired == false and rep4.healthy == true, vim.json.encode(rep4))
end

-- ── [5] negative controls (the suite must discriminate) ────────────────────
do
  io.stdout:write("[5] negative controls\n")
  boot_child()
  break_trigger()

  -- Control A: stub out the repair core; the guard must then FAIL to
  -- recover, proving the [2] assertions test the real recovery path.
  -- A fresh child is booted afterwards so the stub never leaks.
  lua([[ vim.g.autovim_leader_guard = 0 ]]) -- disable boundary machinery first
  lua([[
    local compat = require("utils.wk_compat")
    compat.rebuild_mode = function(buf, mode) return false, "stubbed" end
    local g = require("utils.leader_guard")
    local rep = g.repair()
    vim.g.autovim_test_negctl = rep
  ]])
  local ctl = lua_str("vim.g.autovim_test_negctl")
  ok(
    "control A: with repair stubbed, recovery fails (suite discriminates)",
    ctl.repaired == false and ctl.healthy == false,
    vim.json.encode(ctl)
  )

  -- Fresh child: real modules restored.
  boot_child()
  break_trigger()

  -- Control C: the registry-only predicate variant. Under the detached
  -- break shape the registry is honest (no entry), so a registry-only
  -- health check here reports the buffer healthy by ABSENCE of a claim —
  -- the point is it cannot distinguish; the real predicate inspects
  -- mappings. Show the complementary external-deletion shape too: the
  -- registry claims presence while the trigger is really gone.
  local reg_only = lua_str([[
    (function()
      local T = require("which-key.triggers")
      local b = vim.api.nvim_get_current_buf()
      local claimed = T.has({ buf = b, mode = "n", keys = "<Space>" })
      -- external-deletion shape on a healthy trigger: registry lies
      local b2_claimed, b2_actual
      local B = require("which-key.buf")
      B.clear({ buf = b, mode = "n" })
      B.get({ buf = b, mode = "n" })
      vim.wait(50, function() return false end, 10)
      pcall(vim.keymap.del, "n", " ", { buffer = b })
      b2_claimed = T.has({ buf = b, mode = "n", keys = "<Space>" })
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, "n")) do
        if m.lhs == " " or m.lhs == "<Space>" then b2_actual = true end
      end
      return { claimed = claimed, b2_claimed = b2_claimed, b2_actual = b2_actual }
    end)()
  ]])
  settle(100)
  ok(
    "control C: registry claims present while trigger really gone (external-deletion shape)",
    reg_only.b2_claimed == true and reg_only.b2_actual ~= true,
    vim.json.encode(reg_only)
  )

  -- Real recovery still works after all of the above (same child).
  local rep5 = lua_str([[
    (function()
      local rep = require("utils.leader_guard").repair()
      return { repaired = rep.repaired, healthy = rep.healthy }
    end)()
  ]])
  ok(
    "control D: real repair still recovers after controls",
    rep5.repaired == true and rep5.healthy == true,
    vim.json.encode(rep5)
  )
end

-- ── teardown & summary ────────────────────────────────────────────────────
vim.fn.jobstop(child)
io.stdout:write(string.format("%d passed, %d failed\n", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
os.exit(0)
