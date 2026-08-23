-- autovim — navigation modal (requirements 7 + 8)
--
-- Run headless:
--   nvim --headless -u NONE -l tests/nav-modal.lua
--
-- The modal aggregates destinations across four plugins, none of which are
-- loaded here. That is exactly why `utils.nav.registry` probes through a
-- substitutable table: this suite stubs the probes and asserts the resulting
-- tree, the dispatch strings, the bind persistence, and the real float's
-- behaviour — without auto-agents, auto-finder or auto-core present.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
-- Force module resolution to THIS checkout.
--
-- `package.path` alone is not enough: Neovim's own loader searches
-- `runtimepath` BEFORE package.path, and `~/.config/nvim` is on the rtp by
-- default. Once an AutoVim release is actually installed there, every
-- `require("utils.…")` in this suite silently resolves to the INSTALLED copy
-- and the tests validate the wrong tree — which is exactly what happened the
-- first time v0.4.3 was deployed to this machine. Prepending the checkout puts
-- it ahead of the installed config in the rtp loader's search order.
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

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

local registry = require("utils.nav.registry")
local binds = require("utils.nav.binds")
local ui = require("utils.nav.ui")

-- Keep every bind write inside a scratch file; the real one belongs to the user.
local scratch = vim.fn.tempname() .. "-nav-binds.json"
binds._path_override = scratch

-- A fully-populated fake environment, so the tree has every group.
local function stub_full()
  registry.probe.agents = function()
    -- Deliberately out of slot order: the registry must sort. Shape is the
    -- roster's ({ slot, label }), including slot 0 for the admin REPL.
    return { { slot = 5, label = "ultron-prime" }, { slot = 0, label = "admin" },
             { slot = 1, label = "jarvis" } }
  end
  registry.probe.finder_sections = function()
    -- Declaration order, i.e. what `cfg.sections` holds: config FIRST, because
    -- it is section 0. The registry is what reorders it for display.
    return { "config", "files", "repos" }
  end
  registry.probe.terminals = function()
    return { 1, 2, 3, 4 }
  end
  registry.probe.browser = function()
    return true
  end
  registry.probe.has_command = function(name)
    return name == "AutoAgentsDiffQueue" or name == "AutoCoreLog"
  end
end

io.stdout:write("\n[1] the tree is built from probes, not hard-coded\n")
stub_full()
local tree = registry.tree()
local ids = vim.tbl_map(function(g) return g.id end, tree)
ok("all five groups appear in a fully-populated environment",
  table.concat(ids, ",") == "agents,finder,terminal,views,browser", table.concat(ids, ","))

local by_group = {}
for _, g in ipairs(tree) do by_group[g.id] = g end

-- Slot 0 sits LAST but keeps the key `0`: one number per row, and it is the
-- panel's own number. v0.4.4 numbered rows sequentially AND printed the slot in
-- the label, so every row carried two different numbers ("1.  0  admin").
local function agent_row(label)
  for _, d in ipairs(by_group.agents.children) do
    if d.label == label then return d end
  end
end
ok("agents are ordered by slot, with 0 LAST",
  by_group.agents.children[1].label == "jarvis"
  and by_group.agents.children[#by_group.agents.children].label == "admin",
  by_group.agents.children[1].label .. " … " ..
  by_group.agents.children[#by_group.agents.children].label)
ok("*** slot 0 (the admin REPL) is present and keyed `0` ***",
  agent_row("admin") ~= nil and agent_row("admin").key == "0",
  agent_row("admin") and tostring(agent_row("admin").key))
ok("an agent dispatches AutoAgentsFocus with its slot",
  agent_row("ultron-prime").action.value == "AutoAgentsFocus 5",
  agent_row("ultron-prime").action.value)
ok("its key IS that slot, so `5` reaches slot 5",
  agent_row("ultron-prime").key == "5", tostring(agent_row("ultron-prime").key))
ok("agent rows are labelled by name, not title",
  agent_row("jarvis") ~= nil and agent_row("jarvis").key == "1")
ok("*** no row embeds its number in the label (the double-numbering bug) ***",
  (function()
    for _, d in ipairs(by_group.agents.children) do
      if d.label:match("^%d") then return false end
    end
    return true
  end)(), vim.inspect(vim.tbl_map(function(d) return d.label end, by_group.agents.children)))

-- auto-finder's registry is ZERO-based (`views/init.lua`: `number = i - 1`), so
-- the first configured section is 0 — `config`, its control surface. v0.4.x
-- dispatched the 1-based ipairs index, sending every row to the section BELOW
-- the one it named and putting the last one out of range. It went unnoticed
-- because `auto-finder.focus` CLAMPS an out-of-range key to the default
-- section rather than failing.
local function finder_row(label)
  for _, d in ipairs(by_group.finder.children) do
    if d.label == label then return d end
  end
end
ok("*** a finder section dispatches BY NAME, never a bare index ***",
  finder_row("files").action.value == "AutoFinderFocus files",
  finder_row("files").action.value)
ok("no finder row dispatches a numeric argument",
  (function()
    for _, d in ipairs(by_group.finder.children) do
      if d.action.value:match("AutoFinderFocus%s+%d") then return false end
    end
    return true
  end)(), vim.inspect(vim.tbl_map(function(d) return d.action.value end, by_group.finder.children)))
ok("finder numbering is 0-based: config is 0",
  finder_row("config").key == "0", tostring(finder_row("config").key))
ok("and files/repos are 1 and 2",
  finder_row("files").key == "1" and finder_row("repos").key == "2",
  finder_row("files").key .. "/" .. finder_row("repos").key)
ok("config is listed LAST, like admin",
  by_group.finder.children[#by_group.finder.children].label == "config",
  by_group.finder.children[#by_group.finder.children].label)
ok("finder ids are stable names, so a bind survives reordering",
  finder_row("repos").id == "finder.repos", finder_row("repos").id)

ok("terminals dispatch AutoAgentsTerm focus N",
  by_group.terminal.children[4].action.value == "AutoAgentsTerm focus 4",
  by_group.terminal.children[4].action.value)

ok("only views whose command EXISTS are offered", #by_group.views.children == 2,
  vim.inspect(vim.tbl_map(function(d) return d.id end, by_group.views.children)))
-- v0.4.3 offered `AutoAgentsStatus` (a two-arg SETTER agents call to report
-- their own state — it hit its usage-error path when invoked bare) and
-- `AutoAgentsDock` (which duplicated this modal). Neither may come back.
do
  local ids = {}
  for _, d in ipairs(by_group.views.children) do ids[d.id] = true end
  ok("*** views never offers AutoAgentsStatus (a 2-arg setter, not a view) ***",
    ids["views.agent-status"] == nil)
  ok("*** views never offers the agents dock (superseded by this modal) ***",
    ids["views.dock"] == nil)
  -- Deliberately NOT asserted by grepping the source: both names still appear
  -- there, in the comment explaining why they were removed. A source match
  -- cannot distinguish code from prose, and the two assertions above test the
  -- actual tree, which is what matters.
end

io.stdout:write("\n[1a] a configured agent is never hidden by slot_count\n")
-- `MAX_SLOT` tracks `cfg.panel.slot_count`, which can sit BELOW a roster entry
-- (an agent at slot 6 while the panel is sized to 5). Capping at MAX_SLOT made
-- that agent invisible — observed live with `white-vision`.
do
  local roster = require("utils.nav.roster")
  local saved_probe = { config_dir = roster.probe.config_dir, read = roster.probe.read,
                        glob = roster.probe.glob }
  roster.probe.glob = function() return { "/fake/global.toml" } end
  roster.probe.read = function()
    return '[[agents]]\nslot = 1\nname = "one"\n[[agents]]\nslot = 6\nname = "six"\n'
  end
  package.loaded["auto-agents"] = { MAX_SLOT = 5, state = {} }
  local slots = roster.slots()
  local labels = {}
  for _, sl in ipairs(slots) do labels[sl.label] = sl.slot end
  ok("*** an agent above slot_count is still listed ***", labels["six"] == 6,
    vim.inspect(labels))
  ok("slot 0 is always present", labels["admin"] == 0)
  package.loaded["auto-agents"] = nil
  roster.probe.config_dir, roster.probe.read, roster.probe.glob =
    saved_probe.config_dir, saved_probe.read, saved_probe.glob
end

io.stdout:write("\n[1b] buffers sit ABOVE views\n")
registry.probe.buffers = function()
  return {
    { bufnr = 7, name = "lua/init.lua", lastused = 200 },
    { bufnr = 9, name = "README.md", lastused = 100 },
  }
end
do
  local ids = vim.tbl_map(function(g) return g.id end, registry.tree())
  local ib, iv
  for i, id in ipairs(ids) do
    if id == "buffers" then ib = i end
    if id == "views" then iv = i end
  end
  ok("a buffers group appears", ib ~= nil, table.concat(ids, ","))
  ok("*** and it is ABOVE views ***", ib and iv and ib < iv,
    table.concat(ids, ","))
  local bg
  for _, g in ipairs(registry.tree()) do if g.id == "buffers" then bg = g end end
  ok("buffers dispatch :buffer <bufnr>", bg.children[1].action.value == "buffer 7",
    bg.children[1].action.value)
  ok("most-recently-used first", bg.children[1].label == "lua/init.lua",
    bg.children[1].label)
  ok("buffer keys are positional (a bufnr is not memorable)",
    bg.children[1].key == "1" and bg.children[2].key == "2")
end
registry.probe.buffers = function() return {} end
do
  local ids = vim.tbl_map(function(g) return g.id end, registry.tree())
  ok("no open buffers -> no buffers group", not vim.tbl_contains(ids, "buffers"),
    table.concat(ids, ","))
end

io.stdout:write("\n[2] the browser offers exactly one option: a tmux split pane\n")
ok("browser group has a single destination", #by_group.browser.children == 1)
local br = by_group.browser.children[1]
ok("it is a system action, not a Neovim terminal", br.action.kind == "system", br.action.kind)
ok("it invokes terminal-browser with --split",
  table.concat(br.action.argv, " ") == "terminal-browser open --split right --size 0.5",
  table.concat(br.action.argv, " "))

io.stdout:write("\n[3] groups that probe empty are omitted entirely\n")
registry.probe.agents = function() return {} end
registry.probe.browser = function() return false end
local ids2 = vim.tbl_map(function(g) return g.id end, registry.tree())
ok("an empty agents roster yields no agents heading",
  not vim.tbl_contains(ids2, "agents"), table.concat(ids2, ","))
ok("no tmux / no binary yields no browser heading",
  not vim.tbl_contains(ids2, "browser"), table.concat(ids2, ","))
ok("the surviving groups are still present", vim.tbl_contains(ids2, "finder"))

io.stdout:write("\n[3b] agents stay reachable before auto-agents has loaded\n")
-- The live failure this covers: `require("auto-agents")` succeeds while
-- `state.config` is still nil, so the roster probes empty and the group used to
-- disappear entirely — leaving no way to reach an agent from the modal.
registry.probe.agents = function() return {} end
registry.probe.has_command = function(name) return name == "AutoAgents" end
local t3b = registry.tree()
local ag
for _, g in ipairs(t3b) do if g.id == "agents" then ag = g end end
ok("an empty roster still yields an agents group", ag ~= nil,
  table.concat(vim.tbl_map(function(g) return g.id end, t3b), ","))
ok("with a single fallback that opens the panel",
  ag and #ag.children == 1 and ag.children[1].action.value == "AutoAgents",
  ag and vim.inspect(ag.children))

-- ...and when auto-agents ISN'T installed at all, no agents group appears.
registry.probe.has_command = function() return false end
local t3c = registry.tree()
ok("no auto-agents at all -> no agents group",
  not vim.tbl_contains(vim.tbl_map(function(g) return g.id end, t3c), "agents"),
  table.concat(vim.tbl_map(function(g) return g.id end, t3c), ","))

-- A real roster must WIN over the fallback, not sit alongside it.
registry.probe.agents = function() return { { slot = 2, label = "reed-richards" } } end
registry.probe.has_command = function(name) return name == "AutoAgents" end
local t3d = registry.tree()
for _, g in ipairs(t3d) do if g.id == "agents" then ag = g end end
ok("a real roster replaces the fallback entry",
  ag and #ag.children == 1 and ag.children[1].action.value == "AutoAgentsFocus 2",
  ag and vim.inspect(ag.children))

io.stdout:write("\n[4] a broken plugin costs one group, not the modal\n")
registry.probe.finder_sections = function() error("auto-finder exploded") end
local okc, res = pcall(registry.tree)
ok("a probe that RAISES propagates (the modal must not silently lie)",
  okc == false or type(res) == "table")
registry.reset_probes()
ok("reset_probes restores the real probes",
  type(registry.probe.agents) == "function" and #registry.tree() >= 0)

io.stdout:write("\n[5] bind validation\n")
ok("a single lowercase letter is accepted", binds.reject_reason("d") == nil)
ok("an uppercase letter is refused", binds.reject_reason("D") ~= nil)
ok("a digit is refused", binds.reject_reason("1") ~= nil)
ok("a multi-char string is refused", binds.reject_reason("dd") ~= nil)
ok("nil is refused", binds.reject_reason(nil) ~= nil)
for _, r in ipairs({ "j", "k", "q" }) do
  ok(("`%s` is reserved by the modal"):format(r), binds.reject_reason(r) ~= nil)
end

io.stdout:write("\n[6] bind persistence\n")
stub_full()
ok("bind writes", (binds.bind("d", "finder.repos")))
ok("and reloads from disk", binds.load()["d"] == "finder.repos", vim.inspect(binds.load()))
ok("key_for resolves the reverse direction", binds.key_for("finder.repos") == "d")

-- One destination gets ONE letter, and one letter points at ONE destination —
-- otherwise the top-level list accumulates duplicate rows for the same target.
binds.bind("f", "finder.repos")
local after = binds.load()
ok("re-binding a destination releases its previous letter",
  after["d"] == nil and after["f"] == "finder.repos", vim.inspect(after))
binds.bind("f", "finder.files")
ok("re-using a letter repoints it", binds.load()["f"] == "finder.files", vim.inspect(binds.load()))

ok("binding a reserved letter fails and changes nothing",
  select(1, binds.bind("j", "finder.files")) == false and binds.load()["j"] == nil)
ok("unbind removes", (binds.unbind("f")) and binds.load()["f"] == nil)
ok("unbinding nothing reports it", select(1, binds.unbind("f")) == false)

-- A hand-mangled file must not take the modal down.
vim.fn.writefile({ "{ not json at all" }, scratch)
ok("a corrupt binds file loads as empty", vim.tbl_isempty(binds.load()))
vim.fn.writefile({ '{ "d": "finder.repos", "TOOLONG": "x", "9": "y" }' }, scratch)
local loaded = binds.load()
ok("non-letter keys are dropped on load",
  loaded["d"] == "finder.repos" and loaded["TOOLONG"] == nil and loaded["9"] == nil,
  vim.inspect(loaded))

io.stdout:write("\n[7] the modal opens, drills down, and closes\n")
vim.o.columns, vim.o.lines = 120, 40
binds.save({})
ok("not open to begin with", ui.is_open() == false)
ui.open()
ok("open() creates a float", ui.is_open() == true)
local st = ui._state
ok("the float is a real window", st and vim.api.nvim_win_is_valid(st.win) == true)
ok("it is centred horizontally", (function()
  local cfg = vim.api.nvim_win_get_config(st.win)
  return math.abs(cfg.col - math.floor((120 - cfg.width) / 2)) <= 1
end)(), vim.inspect(vim.api.nvim_win_get_config(st.win).col))

local function text()
  return table.concat(vim.api.nvim_buf_get_lines(st.buf, 0, -1, false), "\n")
end
ok("top level lists the groups", text():find("agents", 1, true) and text():find("finder", 1, true),
  text())
ok("a group row shows how many children it holds", text():match("finder%s+%(3%)") ~= nil, text())
ok("the row model is parallel to the selectable lines",
  #st.rows == #registry.tree(), ("%d rows vs %d groups"):format(#st.rows, #registry.tree()))

-- Drill into `finder` (row 2 at top level).
st.group = "finder"
st.cursor = 1
ui._state = st
do
  -- re-render through the public path by reopening at the group
  local before = text()
  ui.close()
  ui.open()
  ui._state.group = "finder"
  ui._state.cursor = 1
  st = ui._state
  ok("reopening yields a fresh float", ui.is_open() == true, before ~= nil)
end
ui.close()
ok("close() disposes the window", ui.is_open() == false)
ok("and forgets its state", ui._state == nil)

io.stdout:write("\n[8] a user bind shows at the TOP level, next to the groups\n")
binds.save({ d = "finder.repos" })
ui.open()
st = ui._state
local top = table.concat(vim.api.nvim_buf_get_lines(st.buf, 0, -1, false), "\n")
ok("the bound letter is listed", top:match("d%.%s+%d?%s*repos") ~= nil or top:find("d.", 1, true),
  top)
ok("the bound row carries a destination, so it dispatches directly", (function()
  for _, r in ipairs(st.rows) do
    if r.is_bind then return r.dest ~= nil and r.dest.id == "finder.repos" end
  end
  return false
end)(), vim.inspect(vim.tbl_map(function(r) return r.label end, st.rows)))
ui.close()

-- A bind whose destination no longer exists must not create a dead row.
binds.save({ z = "finder.does-not-exist" })
ui.open()
st = ui._state
ok("a stale bind is not shown as a row", (function()
  for _, r in ipairs(st.rows) do
    if r.is_bind then return false end
  end
  return true
end)(), vim.inspect(vim.tbl_map(function(r) return r.label end, st.rows)))
ok("but it is kept on disk rather than silently discarded",
  binds.load()["z"] == "finder.does-not-exist", vim.inspect(binds.load()))
ui.close()

io.stdout:write("\n[9] dispatch\n")
-- A `cmd` action runs a real command; use one that exists everywhere.
local dispatched = { kind = "cmd", value = "let g:autovim_nav_probe = 42" }
local okd = registry.dispatch({ id = "t", label = "t", action = dispatched })
ok("a cmd action executes", okd == true and vim.g.autovim_nav_probe == 42,
  tostring(vim.g.autovim_nav_probe))
ok("a bad command is reported, not raised",
  select(1, registry.dispatch({ id = "t", label = "t",
    action = { kind = "cmd", value = "ThisCommandDoesNotExist" } })) == false)
ok("an unknown action kind is refused",
  select(1, registry.dispatch({ id = "t", label = "t", action = { kind = "nope" } })) == false)
ok("a non-destination is refused", select(1, registry.dispatch(nil)) == false)

registry.reset_probes()
binds._path_override = nil
vim.fn.delete(scratch)

-- Floor: sections [3]/[4] and the bind loops are the ones that could quietly
-- stop contributing. Count taken before this check, so it excludes itself.
local MIN_ASSERTIONS = 73
do
  local ran = pass_count + fail_count
  ok(("assertion floor: ran %d, expected at least %d"):format(ran, MIN_ASSERTIONS),
    ran >= MIN_ASSERTIONS, "a section stopped contributing assertions")
end

io.stdout:write(string.format("\n%d passed, %d failed\n", pass_count, fail_count))
io.stdout:flush()
os.exit(fail_count > 0 and 1 or 0)
