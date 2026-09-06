-- tests/agent-keymaps.lua — the auto-agents keymap spec, and the two
-- properties of <leader>af that are easy to break silently.
--
-- Johno, 2026-09-07: forwarding a selection did not work. Part of that was a
-- runtime clone two commits behind, but it surfaced that the `<leader>a` GROUP
-- is declared for normal mode only, while `<leader>af` is the sole entry that
-- also binds visual — so in visual mode the prefix has no scaffolding at all.
local root = vim.fn.fnamemodify(
  vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h:h"), ":p")

local pass_count, fail_count = 0, 0
local function ok(n, c, d)
  if c then pass_count = pass_count + 1; io.stdout:write("  PASS  " .. n .. "\n")
  else fail_count = fail_count + 1
    io.stdout:write("  FAIL  " .. n .. (d and ("  — " .. tostring(d)) or "") .. "\n") end
  io.stdout:flush()
end

io.stdout:write("auto-agents keymaps — <leader>a group and <leader>af\n")

local chunk = assert(loadfile(root .. "lua/plugins/auto-agents.lua"))
local spec = assert(chunk())
local keys = spec[1] and spec[1].keys
ok("the auto-agents spec exposes a keys table", type(keys) == "table")

---modes_for normalises lazy.nvim's `mode` field, which is absent (meaning
---normal), a string, or a list.
local function modes_for(entry)
  local m = entry.mode
  if m == nil then return { n = true } end
  if type(m) == "string" then return { [m] = true } end
  local out = {}
  for _, v in ipairs(m) do out[v] = true end
  return out
end

local function entries_for(lhs)
  local out = {}
  for _, e in ipairs(keys or {}) do
    if e[1] == lhs then out[#out + 1] = e end
  end
  return out
end

local function modes_union(lhs)
  local u = {}
  for _, e in ipairs(entries_for(lhs)) do
    for m in pairs(modes_for(e)) do u[m] = true end
  end
  return u
end

-- ── the group prefix ────────────────────────────────────────────────
local group = modes_union("<leader>a")
ok("<leader>a group is declared", next(group) ~= nil)
ok("<leader>a group covers NORMAL mode", group.n == true)
-- The one this suite exists for. Without it, which-key has no group to show in
-- visual mode, so the only visual binding under the prefix is undiscoverable —
-- the prefix looks unmapped even though `af` is there.
ok("<leader>a group covers VISUAL mode", group.x == true or group.v == true,
  "declared for: " .. vim.inspect(vim.tbl_keys(group)))

-- ── <leader>af itself ───────────────────────────────────────────────
local af = entries_for("<leader>af")
ok("<leader>af is bound", #af > 0)
local af_modes = modes_union("<leader>af")
ok("<leader>af works in NORMAL mode (clipboard path)", af_modes.n == true,
  vim.inspect(vim.tbl_keys(af_modes)))
ok("<leader>af works in VISUAL mode (selection path)",
  af_modes.x == true or af_modes.v == true, vim.inspect(vim.tbl_keys(af_modes)))

-- LOAD-BEARING, and the reason the command form is not used here: typing `:`
-- from visual mode LEAVES visual mode before the command runs. Measured — a
-- `:user` command sees mode "n" where a visual keymap sees "V" — so a
-- `<cmd>AutoAgentsForwardText<cr>` rhs could never capture a selection, and
-- before the plugin gained `range = true` it failed outright with
-- `E481: No range allowed`. A Lua function preserves the mode.
for _, e in ipairs(af) do
  ok("<leader>af calls a Lua function, not a <cmd> string",
    type(e[2]) == "function", type(e[2]) == "string" and e[2] or type(e[2]))
end

-- ── the sibling it mirrors ──────────────────────────────────────────
-- <leader>ab is the same shape one letter over; if it ever becomes a <cmd>
-- string the two stop mirroring and this file should be the place that says so.
local ab = entries_for("<leader>ab")
ok("<leader>ab is still a Lua function too", #ab > 0 and type(ab[1][2]) == "function")

io.stdout:write(string.format("\n%d passed, %d failed\n", pass_count, fail_count))
os.exit(fail_count > 0 and 1 or 0)
