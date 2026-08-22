-- autovim — config smoke test driver
--
-- Run headless:
--   nvim --headless -u NONE -l tests/smoke.lua
--
-- AutoVim is a Neovim *distribution config*, not a plugin, so there is no
-- public Lua API to drive and no runtime behaviour to assert headlessly.
-- What CAN break silently is the config surface itself: a plugin spec that
-- stops being valid Lua (a bad branch-sibling rebase leaving a conflict
-- marker, a stray syntax slip) or a malformed caret version pin — either
-- one bricks the whole config on the next launch, and the break is most
-- visible here because this is the repo the user lives in.
--
-- This driver validates that surface WITHOUT booting the full distro (no
-- lazy.nvim install, no plugin loading): it loads every lua/plugins/*.lua
-- and asserts each is valid Lua returning a spec table, checks that every
-- caret version pin is well-formed (^X.Y.Z), and compile-checks every
-- lua/config/*.lua + init.lua (loadfile catches conflict markers and
-- syntax errors without executing their editor side effects).
--
-- Per the family runner contract (shared/conventions/lua-nvim-plugin-development.md):
-- `-u NONE -l`, a printed `<P> passed, <F> failed` summary, explicit exit.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local pass_count, fail_count = 0, 0
local function ok(name, cond, detail)
  if cond then
    pass_count = pass_count + 1
    print("  PASS  " .. name)
  else
    fail_count = fail_count + 1
    print("  FAIL  " .. name .. "  " .. tostring(detail or ""))
  end
end

-- Recursively collect every `version` string in a (possibly nested) spec tree.
local function collect_versions(node, out)
  if type(node) ~= "table" then return out end
  for k, v in pairs(node) do
    if k == "version" and type(v) == "string" then out[#out + 1] = v end
    if type(v) == "table" then collect_versions(v, out) end
  end
  return out
end

print("\n[1] every lua/plugins/*.lua spec is valid Lua returning a table")
local specs = vim.fn.glob(root .. "/lua/plugins/*.lua", false, true)
ok("found plugin spec files", #specs > 0, "count=" .. #specs)
local all_versions = {}
for _, f in ipairs(specs) do
  local name = vim.fn.fnamemodify(f, ":t")
  local chunk, lerr = loadfile(f)
  if not chunk then
    ok("spec loads: " .. name, false, lerr)
  else
    local okc, res = pcall(chunk)
    ok("spec loads + returns a table: " .. name,
      okc and type(res) == "table",
      okc and ("returned " .. type(res)) or tostring(res))
    if okc and type(res) == "table" then collect_versions(res, all_versions) end
  end
end

print("\n[2] every caret version pin is well-formed (^X.Y.Z)")
ok("found version pins to check", #all_versions > 0, "count=" .. #all_versions)
for _, v in ipairs(all_versions) do
  -- Only caret pins are constrained here; exact tags, "*", and false are
  -- all valid lazy `version` values and left alone.
  if v:sub(1, 1) == "^" then
    ok("caret pin well-formed: " .. v, v:match("^%^%d+%.%d+%.%d+$") ~= nil, v)
  end
end

print("\n[3] every lua/config/*.lua compiles (loadfile — no execution)")
local cfgs = vim.fn.glob(root .. "/lua/config/*.lua", false, true)
ok("found config files", #cfgs > 0, "count=" .. #cfgs)
for _, f in ipairs(cfgs) do
  local name = vim.fn.fnamemodify(f, ":t")
  local chunk, lerr = loadfile(f)
  ok("config compiles: " .. name, chunk ~= nil, lerr)
end

print("\n[4] init.lua compiles")
local _, init_err = loadfile(root .. "/init.lua")
ok("init.lua compiles", init_err == nil, init_err)

print(string.format("\n%d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
os.exit(0)
