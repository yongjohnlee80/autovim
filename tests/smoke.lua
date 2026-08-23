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

-- Specs are EXECUTED below, and a spec may legitimately `require` one of the
-- config's own modules (`plugins/theme.lua` requires `utils.platform`). Make
-- the config's lua/ resolvable before anything runs, or section [1] fails for
-- a reason that has nothing to do with the spec being malformed.
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

-- Recursively collect every `version` string in a (possibly nested) spec tree.
local function collect_versions(node, out)
  if type(node) ~= "table" then return out end
  for k, v in pairs(node) do
    if k == "version" and type(v) == "string" then out[#out + 1] = v end
    if type(v) == "table" then collect_versions(v, out) end
  end
  return out
end

-- Collect every plugin that carries a CARET version pin, as
-- `{ repo = "owner/name", name = <lazy name>, version = "^X.Y.Z" }`.
--
-- These are the plugins AutoVim itself version-manages (the family repos), and
-- they are exactly where the lock file drifted: `autodb` and `auto-run.nvim`
-- were declared with caret pins but had NO lazy-lock.json entry, so a
-- lock-driven fresh install simply never materialised them. Section [12] turns
-- that into a hard failure.
local function collect_pinned(node, out)
  if type(node) ~= "table" then return out end
  if type(node[1]) == "string" and type(node.version) == "string"
    and node.version:sub(1, 1) == "^" then
    local repo = node[1]
    out[#out + 1] = {
      repo = repo,
      -- lazy derives a plugin's name from `name` when given, else the repo's
      -- basename. The lock file is keyed by that same name.
      name = node.name or repo:match("([^/]+)$"),
      version = node.version,
    }
  end
  for _, v in pairs(node) do
    if type(v) == "table" then collect_pinned(v, out) end
  end
  return out
end

io.stdout:write("\n[1] every lua/plugins/*.lua spec is valid Lua returning a table\n")
local specs = vim.fn.glob(root .. "/lua/plugins/*.lua", false, true)
ok("found plugin spec files", #specs > 0, "count=" .. #specs)
local all_versions = {}
local all_pinned = {}
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
    if okc and type(res) == "table" then
      collect_versions(res, all_versions)
      collect_pinned(res, all_pinned)
    end
  end
end

io.stdout:write("\n[2] every caret version pin is well-formed (^X.Y.Z)\n")
ok("found version pins to check", #all_versions > 0, "count=" .. #all_versions)
for _, v in ipairs(all_versions) do
  -- Only caret pins are constrained here; exact tags, "*", and false are
  -- all valid lazy `version` values and left alone.
  if v:sub(1, 1) == "^" then
    ok("caret pin well-formed: " .. v, v:match("^%^%d+%.%d+%.%d+$") ~= nil, v)
  end
end

io.stdout:write("\n[3] every lua/config/*.lua compiles (loadfile — no execution)\n")
local cfgs = vim.fn.glob(root .. "/lua/config/*.lua", false, true)
ok("found config files", #cfgs > 0, "count=" .. #cfgs)
for _, f in ipairs(cfgs) do
  local name = vim.fn.fnamemodify(f, ":t")
  local chunk, lerr = loadfile(f)
  ok("config compiles: " .. name, chunk ~= nil, lerr)
end

io.stdout:write("\n[4] init.lua compiles\n")
local _, init_err = loadfile(root .. "/init.lua")
ok("init.lua compiles", init_err == nil, init_err)

io.stdout:write("\n[5] platform detection (utils.platform) — every OS branch, stubbed\n")
local platform = require("utils.platform")

-- Real reading first, as a sanity anchor: whatever this box is, the three
-- predicates must be mutually consistent.
local real_sys = platform.sysname()
ok("sysname reports something", type(real_sys) == "string" and real_sys ~= "", real_sys)
ok("macOS and Linux are not both true", not (platform.is_macos() and platform.is_linux()))
ok("Omarchy implies Linux", (not platform.is_omarchy()) or platform.is_linux())

-- Darwin: is_macos, and NEVER Omarchy even if an omarchy dir somehow exists.
platform.probe.sysname = function() return "Darwin" end
platform.probe.isdir = function() return true end
platform.probe.executable = function() return true end
ok("stubbed Darwin -> is_macos", platform.is_macos() == true)
ok("stubbed Darwin -> not is_linux", platform.is_linux() == false)
ok("Darwin is never Omarchy even with the markers present",
  platform.is_omarchy() == false)
ok("Darwin exposes no Omarchy theme spec", platform.omarchy_theme_spec() == nil)
ok("Darwin exposes no Omarchy theme name", platform.omarchy_theme_name() == nil)

-- Linux WITHOUT Omarchy: the plain-Ubuntu/Arch case.
platform.probe.sysname = function() return "Linux" end
platform.probe.isdir = function() return false end
platform.probe.executable = function() return false end
ok("Linux without markers -> not Omarchy", platform.is_omarchy() == false)
ok("plain Linux exposes no theme spec", platform.omarchy_theme_spec() == nil)

-- Linux WITH the omarchy dir but no readable spec (partially provisioned box):
-- root presence must NOT imply spec presence.
platform.probe.isdir = function() return true end
platform.probe.readable = function() return false end
ok("omarchy dir present -> is_omarchy", platform.is_omarchy() == true)
ok("but an unreadable spec yields nil, not a path",
  platform.omarchy_theme_spec() == nil)

-- Detected via the `omarchy` executable alone (no ~/.config/omarchy).
platform.probe.isdir = function() return false end
platform.probe.executable = function(e) return e == "omarchy" end
ok("omarchy on PATH alone -> is_omarchy", platform.is_omarchy() == true)

platform.reset_probes()
ok("reset_probes restores the real sysname", platform.sysname() == real_sys)

io.stdout:write("\n[6] theme resolution (utils.theme_resolve) — the pure decision table\n")
local resolve = require("utils.theme_resolve")

-- Requirement 5 pins this exact default; if someone edits it, say so loudly.
ok("the non-Omarchy default is catppuccin-mocha",
  resolve.FALLBACK == "catppuccin-mocha", resolve.FALLBACK)

local function decides(label, input, want_name, want_reason)
  local got_name, got_reason = resolve.decide(input)
  ok(label, got_name == want_name and got_reason == want_reason,
    ("got %s/%s want %s/%s"):format(tostring(got_name), tostring(got_reason),
      want_name, want_reason))
end

decides("not Omarchy, no pick -> the distribution default",
  { omarchy = false }, "catppuccin-mocha", "default")
decides("not Omarchy, a saved pick wins",
  { omarchy = false, cached = "gruvbox" }, "gruvbox", "autovim-cache")
decides("Omarchy, no pick -> the system theme",
  { omarchy = true, omarchy_theme = "nord", omarchy_colorscheme = "nord" },
  "nord", "omarchy-system")
decides("Omarchy, a pick stamped with the CURRENT system theme is an override",
  { omarchy = true, omarchy_theme = "nord", omarchy_colorscheme = "nord",
    cached = "gruvbox", cached_stamp = "nord" },
  "gruvbox", "autovim-override")
-- The load-bearing rule: the system theme moving on retires the override.
decides("Omarchy, a pick stamped with a STALE system theme yields to the system",
  { omarchy = true, omarchy_theme = "tokyonight", omarchy_colorscheme = "tokyonight",
    cached = "gruvbox", cached_stamp = "nord" },
  "tokyonight", "omarchy-system")
decides("Omarchy, an UNSTAMPED legacy pick resolves toward the system",
  { omarchy = true, omarchy_theme = "nord", omarchy_colorscheme = "nord",
    cached = "gruvbox" },
  "nord", "omarchy-system")
decides("Omarchy with no usable spec falls back to the saved pick",
  { omarchy = true, cached = "gruvbox" }, "gruvbox", "autovim-cache")
decides("Omarchy with neither spec nor pick lands on the default",
  { omarchy = true }, "catppuccin-mocha", "default")
decides("a nil input table does not crash", {}, "catppuccin-mocha", "default")

io.stdout:write("\n[7] reading a colorscheme out of an Omarchy lazy fragment\n")
ok("extracts opts.colorscheme from the LazyVim entry",
  resolve.colorscheme_of({
    { "catppuccin/nvim", name = "catppuccin" },
    { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
  }) == "catppuccin")
ok("nil fragment -> nil", resolve.colorscheme_of(nil) == nil)
ok("non-table fragment -> nil", resolve.colorscheme_of("nope") == nil)
ok("fragment with no LazyVim entry -> nil",
  resolve.colorscheme_of({ { "catppuccin/nvim" } }) == nil)
ok("LazyVim entry with no opts -> nil",
  resolve.colorscheme_of({ { "LazyVim/LazyVim" } }) == nil)
ok("LazyVim entry with an empty colorscheme -> nil",
  resolve.colorscheme_of({ { "LazyVim/LazyVim", opts = { colorscheme = "" } } }) == nil)
ok("a non-string colorscheme -> nil",
  resolve.colorscheme_of({ { "LazyVim/LazyVim", opts = { colorscheme = 42 } } }) == nil)

io.stdout:write("\n[8] theme cache round-trip (v2 stamp + v1 backward compatibility)\n")
local cache = require("utils.theme_cache")
local scratch = vim.fn.tempname() .. "-theme-cache.txt"
cache._path_override = scratch

cache.save("gruvbox", "nord")
local rec = cache.load_full()
ok("saves and reloads the name", rec.name == "gruvbox", vim.inspect(rec))
ok("saves and reloads the Omarchy stamp", rec.omarchy_stamp == "nord", vim.inspect(rec))
ok("load() still returns just the name", cache.load() == "gruvbox")

cache.save("everforest")
rec = cache.load_full()
ok("saving without a stamp clears the old one",
  rec.name == "everforest" and rec.omarchy_stamp == nil, vim.inspect(rec))

-- A v1 file is a bare name with no trailing newline handling to rely on.
local fh = assert(io.open(scratch, "w"))
fh:write("habamax")
fh:close()
rec = cache.load_full()
ok("a v1 (name-only) cache file still loads", rec.name == "habamax", vim.inspect(rec))
ok("and carries no stamp", rec.omarchy_stamp == nil)

cache.save("", "nord")
ok("an empty name is refused, leaving the file untouched",
  cache.load() == "habamax", tostring(cache.load()))

ok("clear() removes the file", cache.clear() and cache.load() == nil)
ok("load_full() on a missing file returns an empty record",
  next(cache.load_full()) == nil)
cache._path_override = nil
vim.fn.delete(scratch)

io.stdout:write("\n[9] the resolved default theme is actually installable\n")
-- Requirement 4's whole complaint is specs that name plugins the lock file
-- cannot supply. The default colorscheme is the worst possible instance of
-- that bug, so pin it: the plugin backing FALLBACK must be both declared and
-- locked. `catppuccin-mocha` is a flavour of the `catppuccin` plugin.
local themes_src = table.concat(vim.fn.readfile(root .. "/lua/plugins/all-themes.lua"), "\n")
ok("the fallback theme's plugin is declared in all-themes.lua",
  themes_src:find("catppuccin/nvim", 1, true) ~= nil)
local lock_path = root .. "/lazy-lock.json"
ok("lazy-lock.json exists (requirement 4)", vim.fn.filereadable(lock_path) == 1)
local lock_ok, lock = pcall(vim.json.decode, table.concat(vim.fn.readfile(lock_path), "\n"))
ok("lazy-lock.json is valid JSON", lock_ok and type(lock) == "table",
  lock_ok and "ok" or tostring(lock))
if lock_ok and type(lock) == "table" then
  ok("the fallback theme's plugin is present in the lock file",
    lock["catppuccin"] ~= nil)
end

io.stdout:write("\n[10] OS-gated specs contribute only on their own platform\n")
-- `gopls.lua` is what replaced the `mac-os` branch. The gate is the entire
-- point, so assert BOTH directions: a gate that never closes is invisible in a
-- green run on a single machine.
local function spec_entries(rel)
  local chunk, lerr = loadfile(root .. "/" .. rel)
  if not chunk then
    return nil, lerr
  end
  local okc, res = pcall(chunk)
  if not okc or type(res) ~= "table" then
    return nil, tostring(res)
  end
  return #res
end

platform.probe.sysname = function() return "Darwin" end
local n_gopls_mac, e1 = spec_entries("lua/plugins/gopls.lua")
ok("gopls.lua contributes its Mason bypass on macOS", n_gopls_mac == 1, tostring(n_gopls_mac or e1))
local n_theme_mac = spec_entries("lua/plugins/theme.lua")
ok("theme.lua always contributes on macOS", (n_theme_mac or 0) >= 1, tostring(n_theme_mac))

platform.probe.sysname = function() return "Linux" end
platform.probe.isdir = function() return false end
platform.probe.executable = function() return false end
local n_gopls_linux = spec_entries("lua/plugins/gopls.lua")
ok("gopls.lua contributes NOTHING on plain Linux (Mason keeps gopls)",
  n_gopls_linux == 0, tostring(n_gopls_linux))
local n_theme_linux = spec_entries("lua/plugins/theme.lua")
ok("theme.lua always contributes on Linux", (n_theme_linux or 0) >= 1, tostring(n_theme_linux))
platform.reset_probes()

io.stdout:write("\n[11] no branch-only artefact survives on a shared main\n")
-- The consolidation's failure mode is a leftover: a tracked SYMLINK where a Lua
-- file belongs. The `omarchy` branch shipped `theme.lua` as a symlink into
-- ~/.config/omarchy, which is exactly what cannot live on a shared main.
for _, rel in ipairs({ "lua/plugins/theme.lua", "lua/plugins/gopls.lua" }) do
  ok(rel .. " is a real file, not a symlink",
    vim.fn.getftype(root .. "/" .. rel) == "file",
    vim.fn.getftype(root .. "/" .. rel))
end

-- The Omarchy hot-reload is wired in `config/autocmds.lua`, not as a spec. See
-- section [13] for WHY, and for the guard that keeps it that way.
local autocmds_src = table.concat(vim.fn.readfile(root .. "/lua/config/autocmds.lua"), "\n")
ok("the Omarchy hot-reload is gated behind is_omarchy()",
  autocmds_src:find('is_omarchy()', 1, true) ~= nil)
ok("and it listens for Omarchy's LazyReload signal",
  autocmds_src:find('pattern = "LazyReload"', 1, true) ~= nil)
ok("the retired hot-reload SPEC is gone from lua/plugins/",
  vim.fn.filereadable(root .. "/lua/plugins/omarchy-theme-hotreload.lua") == 0)

io.stdout:write("\n[12] no two plugin specs claim the same local `dir`\n")
-- lazy dedupes LOCAL plugins by `dir`: give two specs the same `dir` and only
-- the first survives — silently, with no warning and no error. That is a real
-- bug this repo already shipped: `omarchy-theme-hotreload.lua` declared
-- `dir = vim.fn.stdpath("config")`, which `theme-picker.lua` already claimed,
-- so the hot-reload was never registered and Omarchy theme switching quietly
-- did nothing. Anything config-local belongs in `lua/config/`; if a spec really
-- must be a pseudo-plugin, its `dir` has to be unique.
local dir_claims = {}
local function claim_dirs(node, file)
  if type(node) ~= "table" then return end
  if type(node.dir) == "string" then
    dir_claims[node.dir] = dir_claims[node.dir] or {}
    table.insert(dir_claims[node.dir], (node.name or node[1] or "?") .. " (" .. file .. ")")
  end
  for _, v in pairs(node) do
    if type(v) == "table" then claim_dirs(v, file) end
  end
end
for _, f in ipairs(specs) do
  local chunk = loadfile(f)
  if chunk then
    local okc, res = pcall(chunk)
    if okc and type(res) == "table" then
      claim_dirs(res, vim.fn.fnamemodify(f, ":t"))
    end
  end
end
local dup_found = false
for dir, claimants in pairs(dir_claims) do
  if #claimants > 1 then
    dup_found = true
    ok("duplicate local dir: " .. dir, false, table.concat(claimants, " AND "))
  end
end
ok("every local `dir` is claimed by at most one spec", not dup_found)

io.stdout:write("\n[13] every caret-pinned plugin is suppliable by lazy-lock.json\n")
-- Requirement 4, stated as an assertion. A caret pin says "AutoVim manages this
-- plugin's version"; a committed lock says "these are the versions we support".
-- A plugin with the first and not the second is the `autodb` bug: declared,
-- expected, and silently absent on a fresh install.
--
-- LIMIT OF THIS CHECK, so nobody reads more into a green than is there: it
-- proves PRESENCE, not SATISFACTION. The lock stores commit SHAs, so deciding
-- whether the locked commit actually falls inside `^X.Y.Z` needs the plugin's
-- git history, which a headless config-surface suite cannot assume is checked
-- out. A lock left pointing at a v0.1.x commit after the caret moved to ^0.2.0
-- would still pass here and would still hand a fresh install the wrong version.
-- That is what the release step in [[autovim-release-workflow]] §4d exists for:
-- regenerate the lock from a known-good install whenever a caret moves, and
-- verify with `git describe --tags --exact-match <locked-sha>` per plugin.
ok("found caret-pinned plugins to check", #all_pinned > 0, "count=" .. #all_pinned)
local lock_tbl
do
  local raw = vim.fn.filereadable(root .. "/lazy-lock.json") == 1
    and table.concat(vim.fn.readfile(root .. "/lazy-lock.json"), "\n") or nil
  local decoded_ok, decoded = pcall(vim.json.decode, raw or "")
  lock_tbl = decoded_ok and type(decoded) == "table" and decoded or nil
end
ok("lazy-lock.json decodes for the pin cross-check", lock_tbl ~= nil)
for _, pin in ipairs(all_pinned) do
  ok(("locked: %s (%s)"):format(pin.name, pin.version),
    lock_tbl ~= nil and lock_tbl[pin.name] ~= nil,
    "declared with a caret pin but absent from lazy-lock.json — a fresh install "
      .. "will not materialise it")
end

io.stdout:write("\n[14] the declared Neovim floor is stated once and consistently\n")
-- The floor is 0.11.2, set by LazyVim, and it is a HARD abort:
-- `lazyvim/plugins/init.lua` prints "LazyVim requires Neovim >= 0.11.2", waits
-- for a keypress and runs `:quit`. So an install that passes a too-low gate
-- does not degrade — it hands the user an editor that cannot start.
--
-- install.sh gated at 0.10.0 until v0.4.2, which meant a Debian/Ubuntu box
-- already carrying nvim 0.10.x satisfied the check, skipped the snap install,
-- and then could not launch. This pins the number in one place and asserts the
-- docs agree, so the two cannot drift apart again silently.
--
-- What this CANNOT check: whether 0.11.2 is still what LazyVim requires. That
-- lives in the pinned LazyVim commit, not in this repo. When LazyVim moves its
-- floor, `NVIM_MIN` in install.sh has to be moved by hand.
local NVIM_MIN = "0.11.2"
local install_src = table.concat(vim.fn.readfile(root .. "/install.sh"), "\n")
ok("install.sh declares NVIM_MIN once, as a constant",
  install_src:match('NVIM_MIN="([%d%.]+)"') == NVIM_MIN,
  tostring(install_src:match('NVIM_MIN="([%d%.]+)"')))
ok("install.sh no longer hard-codes a bare 0.10 floor",
  install_src:match('version_ge "%$v" "0%.10') == nil)
ok("install.sh gates on the constant, not a literal",
  install_src:find('version_ge "$v" "$NVIM_MIN"', 1, true) ~= nil)
local readme_src = table.concat(vim.fn.readfile(root .. "/README.md"), "\n")
ok("the README states the same floor", readme_src:find(NVIM_MIN, 1, true) ~= nil)
ok("the README no longer claims 0.10", readme_src:find("≥0.10", 1, true) == nil)

-- Assertion floor. Several sections above are guarded by `if` (the lock-file
-- JSON block only asserts when the decode succeeded), and a section that stops
-- contributing assertions otherwise reports a smaller green number rather than
-- a failure. Pin the count so a silently skipped block is a hard error.
--
-- The count is taken BEFORE this assertion runs, so MIN_ASSERTIONS excludes the
-- floor check itself — the suite's printed total is one higher.
--
-- Registered through `ok()` deliberately, so a shortfall lands in the FAIL list
-- and the printed summary rather than as a bare non-zero exit after a "0
-- failed" line — which reads to the runner like a post-summary crash.
local MIN_ASSERTIONS = 115
do
  local ran = pass_count + fail_count
  ok(("assertion floor: ran %d, expected at least %d"):format(ran, MIN_ASSERTIONS),
    ran >= MIN_ASSERTIONS,
    "a section stopped contributing assertions")
end

io.stdout:write(string.format("\n%d passed, %d failed\n", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
os.exit(0)
