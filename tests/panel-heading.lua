-- utils.panel_heading — the heading above the auto-finder panel names the
-- checkout you are working in (Johno, 2026-09-08).
--
-- Three resolution cases and a truncation ladder, driven against REAL git
-- layouts. The layouts are the point: the workspace this runs in is a
-- CONTAINER of bare repos whose checkouts are named `main` / `<branch>`, so
-- "the repo" and "the directory I am standing in" are different strings, and
-- a basename would answer the wrong one.
--
-- Run headless:  nvim --headless -u NONE -l tests/panel-heading.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

-- auto-core supplies `git.graph.repo_at`. Prefer a sibling checkout that can
-- actually SERVE that call: a stale one would make every repo case silently
-- take the not-a-repo branch, and the suite would report a green that means
-- nothing (the failure mode auto-finder's ADR-0083 suites carry the same
-- guard for).
local sib = vim.fn.fnamemodify(root, ":h:h") .. "/nvim-plugins"
if vim.fn.isdirectory(sib) ~= 1 then
  sib = vim.fn.expand("~/Source/Projects/nvim-plugins")
end
local LAZY = vim.fn.expand("~/.local/share/nvim/lazy")
local core_serves = false
for _, cand in ipairs({
  sib .. "/auto-core.nvim/assign-renotify",
  sib .. "/auto-core.nvim/main",
  LAZY .. "/auto-core.nvim",
}) do
  local f = cand .. "/lua/auto-core/git/graph.lua"
  if vim.fn.filereadable(f) == 1 then
    for _, line in ipairs(vim.fn.readfile(f)) do
      if line:find("function M.repo_at", 1, true) then
        vim.opt.runtimepath:prepend(cand)
        package.path = cand .. "/lua/?.lua;" .. cand .. "/lua/?/init.lua;" .. package.path
        core_serves = true
        break
      end
    end
  end
  if core_serves then break end
end

local pass, fail = 0, 0
local function ok(n, c, d)
  if c then pass = pass + 1; print("  PASS  " .. n)
  else fail = fail + 1; print("  FAIL  " .. n .. (d and ("  — " .. tostring(d)) or "")) end
end

-- An absent instrument must get attention, not be silently skipped: without
-- `repo_at` every repo cell below would take the not-a-repo branch and the
-- suite would read green while measuring nothing.
ok("precondition: an auto-core exposing git.graph.repo_at is on the rtp",
  core_serves, "no sibling or lazy auto-core has repo_at")

local ph = require("utils.panel_heading")

local sb = vim.fn.tempname() .. "-panelheading"
vim.fn.mkdir(sb, "p")
local function G(dir, ...)
  local a = { "git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t",
    "-c", "init.defaultBranch=main" }
  for _, x in ipairs({ ... }) do a[#a + 1] = x end
  return vim.system(a, { text = true }):wait()
end

-- ── the layouts ─────────────────────────────────────────────────────────────

-- A workspace CONTAINER, with an empty `.git/` — the shape this workspace root
-- actually has. It fools `isdirectory`, `vim.fs.find` and every other
-- existence check, while git refuses it.
local ws = sb .. "/nvim-plugins"
vim.fn.mkdir(ws .. "/.git", "p")

-- An ordinary clone inside it.
local plain = ws .. "/plain-proj"
vim.fn.mkdir(plain, "p")
G(plain, "init", "-q", "-b", "main")
vim.fn.writefile({ "x" }, plain .. "/f.txt")
G(plain, "add", "."); G(plain, "commit", "-q", "-m", "one")

-- The bare + linked-worktree layout: the repo is `thing.nvim`, and its
-- checkouts are `thing.nvim/main` and `thing.nvim/side`.
local bare = ws .. "/thing.nvim"
G(ws, "clone", "-q", "--bare", plain, bare)
G(bare, "worktree", "add", "-q", bare .. "/main", "main")
G(bare, "worktree", "add", "-q", "-b", "feat/side-quest", bare .. "/side")

-- ── [1] resolution ──────────────────────────────────────────────────────────

print("\n[1] resolve — which checkout am I in")
do
  -- Stub `utils.scope` so `workspace_root` is the sandbox rather than the
  -- machine's real one; `resolve` takes the dir explicitly, so only the root
  -- (used to relativise the repo label) comes from scope.
  package.loaded["utils.scope"] = {
    workspace_root = function() return ws end,
    active_worktree = function() return nil end,
  }
  ph.invalidate()

  ok("[1] *** a workspace container shows its DIRECTORY name ***",
    ph.resolve(ws) == "[nvim-plugins]", ph.resolve(ws))

  ok("[1] *** an ordinary repo shows [repo - branch] ***",
    ph.resolve(plain) == "[plain-proj - main]", ph.resolve(plain))

  -- The case a basename gets wrong. Standing in `thing.nvim/main`, the
  -- directory is `main` and the repo is `thing.nvim`; Johno asked for
  -- "[repo-name - branch/worktree name]", so both have to be right.
  ok("[1] *** a bare-repo worktree shows the REPO and the branch, not the dir twice ***",
    ph.resolve(bare .. "/main") == "[thing.nvim - main]", ph.resolve(bare .. "/main"))
  ok("[1] *** a second worktree of the same repo differs only by branch ***",
    ph.resolve(bare .. "/side") == "[thing.nvim - feat/side-quest]",
    ph.resolve(bare .. "/side"))

  -- A subdirectory of a repo is still that repo: the question is "which
  -- checkout", not "which folder".
  vim.fn.mkdir(plain .. "/deep/deeper", "p")
  ok("[1] a nested subdirectory resolves to the same repo",
    ph.resolve(plain .. "/deep/deeper") == "[plain-proj - main]",
    ph.resolve(plain .. "/deep/deeper"))

  -- Detached HEAD: no branch to name, so the checkout's directory stands in.
  -- Printing the literal "HEAD" would read like a branch called that.
  local sha = vim.trim(G(bare .. "/side", "rev-parse", "HEAD").stdout or "")
  G(bare .. "/side", "checkout", "-q", sha)
  ok("[1] *** a detached worktree falls back to its directory name, not \"HEAD\" ***",
    ph.resolve(bare .. "/side") == "[thing.nvim - side]", ph.resolve(bare .. "/side"))
  G(bare .. "/side", "checkout", "-q", "feat/side-quest")

  -- A plain directory that is not a repo and not the workspace root.
  local plaindir = sb .. "/somewhere-else"
  vim.fn.mkdir(plaindir, "p")
  ok("[1] a plain directory shows its own name",
    ph.resolve(plaindir) == "[somewhere-else]", ph.resolve(plaindir))

  -- A trailing slash must not produce an empty label.
  ok("[1] a trailing slash does not empty the label",
    ph.resolve(ws .. "/") == "[nvim-plugins]", ph.resolve(ws .. "/"))

  -- A REPO OUTSIDE THE WORKSPACE ROOT still shows its NAME, not a path.
  --
  -- Found by an independent probe against the live workspace, using none of
  -- the fixtures above, which reported:
  --
  --   [~/Source/Projects/nvim-plugins/autovim - feat/panel-titles-and-finder-scope]
  --
  -- `graph.repo_label` returns a `~`-shortened PATH for a repo outside the
  -- root, which is right for the repos panel (a path disambiguates) and wrong
  -- for a 38-column heading (Johno asked for a repo NAME). It is not an edge
  -- case either: it is every repo reached before the session's first
  -- `<leader>gw`, plus the nvim runtime clone and the knowledge base.
  --
  -- The cell that should have caught it instead asserted `repo_label` returns
  -- the `~` path — encoding auto-core's behaviour as correct for THIS consumer
  -- without asking whether a path is what a heading wants.
  local outside = sb .. "/outside-the-workspace"
  vim.fn.mkdir(outside, "p")
  G(outside, "init", "-q", "-b", "trunk")
  vim.fn.writefile({ "x" }, outside .. "/f.txt")
  G(outside, "add", "."); G(outside, "commit", "-q", "-m", "one")
  ok("[1] *** a repo OUTSIDE the workspace root shows its NAME, not a path ***",
    ph.resolve(outside) == "[outside-the-workspace - trunk]", ph.resolve(outside))
  ok("[1] fixture precondition: auto-core really does hand back a path there",
    (function()
      local g = require("auto-core.git.graph")
      local r = g.repo_at(outside, ws)
      return r ~= nil and r.label:find("/", 1, true) ~= nil
    end)(), "auto-core returned a bare name; this cell no longer tests anything")

  -- A repo NESTED under the root gets a relative label (`sub/dir/repo`); the
  -- heading takes the last segment there too.
  local nestdir = ws .. "/group/nested-repo"
  vim.fn.mkdir(nestdir, "p")
  G(nestdir, "init", "-q", "-b", "main")
  vim.fn.writefile({ "x" }, nestdir .. "/f.txt")
  G(nestdir, "add", "."); G(nestdir, "commit", "-q", "-m", "one")
  ok("[1] *** a nested repo shows its own name, not its path under the root ***",
    ph.resolve(nestdir) == "[nested-repo - main]", ph.resolve(nestdir))
  ok("[1] fixture precondition: auto-core labels the nested repo with a path",
    (function()
      local g = require("auto-core.git.graph")
      local r = g.repo_at(nestdir, ws)
      return r ~= nil and r.label == "group/nested-repo"
    end)(), require("auto-core.git.graph").repo_at(nestdir, ws).label)

  -- repo_name in isolation, including the shapes it must leave alone.
  ok("[1] repo_name passes a bare name through untouched",
    ph.repo_name("thing.nvim") == "thing.nvim", ph.repo_name("thing.nvim"))
  ok("[1] repo_name takes the last segment of a relative label",
    ph.repo_name("group/nested-repo") == "nested-repo", ph.repo_name("group/nested-repo"))
  ok("[1] repo_name takes the last segment of a ~-shortened path",
    ph.repo_name("~/.config/nvim") == "nvim", ph.repo_name("~/.config/nvim"))
  ok("[1] repo_name tolerates a trailing slash",
    ph.repo_name("a/b/c/") == "c", ph.repo_name("a/b/c/"))
  ok("[1] repo_name does not crash on nonsense",
    ph.repo_name("") == "" and ph.repo_name("/") == "/",
    ("%q %q"):format(ph.repo_name(""), ph.repo_name("/")))
end

-- ── [2] the scope directory comes from auto-core, not the buffer ────────────

print("\n[2] scope_dir — the worktree <leader>gw set, not the focused buffer")
do
  package.loaded["utils.scope"] = {
    workspace_root = function() return ws end,
    active_worktree = function() return bare .. "/side" end,
  }
  ph.invalidate()
  ok("[2] *** the active worktree wins over cwd ***",
    ph.scope_dir() == bare .. "/side", ph.scope_dir())
  ok("[2] and the label follows it",
    ph.scope_label() == "[thing.nvim - feat/side-quest]", ph.scope_label())

  package.loaded["utils.scope"] = {
    workspace_root = function() return ws end,
    active_worktree = function() return nil end,
  }
  ph.invalidate()
  ok("[2] with no active worktree it falls back to cwd",
    ph.scope_dir() == vim.fs.normalize(vim.fn.getcwd())
      or ph.scope_dir() == vim.fn.getcwd(),
    ph.scope_dir())
end

-- ── [3] the cache ───────────────────────────────────────────────────────────

print("\n[3] the answer is cached against the scope directory")
do
  -- The tabline redraws on every buffer switch, window change and
  -- :redrawtabline. Resolution costs three `git rev-parse` reads, so a
  -- per-frame recompute is the difference between a heading and a stutter.
  local calls = 0
  local real_repo_at = require("auto-core.git.graph").repo_at
  require("auto-core.git.graph").repo_at = function(...)
    calls = calls + 1
    return real_repo_at(...)
  end

  local active = bare .. "/main"
  package.loaded["utils.scope"] = {
    workspace_root = function() return ws end,
    active_worktree = function() return active end,
  }
  ph.invalidate()

  local first = ph.scope_label()
  local after_first = calls
  for _ = 1, 20 do ph.scope_label() end
  ok("[3] *** twenty redraws cost ONE resolution ***",
    calls == after_first and after_first >= 1,
    ("calls=%d after_first=%d"):format(calls, after_first))
  ok("[3] and keep answering the same thing", ph.scope_label() == first, ph.scope_label())

  -- A worktree switch changes the key, so the next redraw recomputes. This is
  -- why there is no event subscription: an invalidation hook would be a second
  -- mechanism that could disagree with the key.
  active = bare .. "/side"
  local switched = ph.scope_label()
  ok("[3] *** switching worktree re-resolves without an invalidation call ***",
    switched == "[thing.nvim - feat/side-quest]" and calls > after_first,
    ("%s calls=%d"):format(switched, calls))

  require("auto-core.git.graph").repo_at = real_repo_at
end

-- ── [4] the truncation ladder ───────────────────────────────────────────────

print("\n[4] heading — shed the prefix first, then ellipsize")
do
  package.loaded["utils.scope"] = {
    workspace_root = function() return ws end,
    active_worktree = function() return bare .. "/side" end,
  }
  ph.invalidate()
  local label = "[thing.nvim - feat/side-quest]"
  local full = "auto-finder: " .. label
  ok("[4] fixture precondition: the label is what the earlier cells resolved",
    ph.scope_label() == label, ph.scope_label())

  ok("[4] with room to spare, everything is shown",
    ph.heading(#full + 10) == full, ph.heading(#full + 10))
  ok("[4] at exactly the full width, everything is shown",
    ph.heading(#full) == full, ph.heading(#full))
  ok("[4] an unknown width shows everything rather than guessing",
    ph.heading(nil) == full, ph.heading(nil))

  -- Johno: "If the text value is too long, we should hide the prefix
  -- 'auto-finder: '". The panel is already identifiable by its position and
  -- contents; WHICH repo you are in is the information.
  ok("[4] *** one column short of the full string drops the PREFIX, not the repo ***",
    ph.heading(#full - 1) == label, ph.heading(#full - 1))
  ok("[4] at exactly the label's width, the label is intact",
    ph.heading(#label) == label, ph.heading(#label))

  -- "...and display ellipsis like '[repos-name - branch name...]'". The
  -- brackets survive, so the heading still reads as one framed value.
  local cut = ph.heading(#label - 4)
  ok("[4] *** below that, the label itself is cut, from the RIGHT ***",
    cut:sub(1, 12) == "[thing.nvim ", cut)
  ok("[4] *** the cut is marked with an ellipsis, inside the brackets ***",
    cut:find("…", 1, true) ~= nil and cut:sub(-1) == "]", cut)
  ok("[4] *** and it FITS the width it was given ***",
    vim.api.nvim_strwidth(cut) <= #label - 4,
    ("%q is %d cells, budget %d"):format(cut, vim.api.nvim_strwidth(cut), #label - 4))

  -- Every width from absurdly small to generous must produce something that
  -- fits. A ladder that overruns by one column corrupts the tabline, and one
  -- hand-picked width would not find it.
  local overruns, empties = {}, {}
  for w = 1, #full + 5 do
    local h = ph.heading(w)
    if vim.api.nvim_strwidth(h) > w then overruns[#overruns + 1] = w end
    if h == "" and w >= 3 then empties[#empties + 1] = w end
  end
  ok("[4] *** no width from 1 to full+5 overruns its budget ***",
    #overruns == 0, vim.inspect(overruns))
  ok("[4] and no usable width produces an empty heading",
    #empties == 0, vim.inspect(empties))

  -- A wide glyph must be measured in CELLS. Slicing by byte or by character
  -- count would push the text past the reserved column.
  ok("[4] *** a double-width glyph is measured in cells, not characters ***",
    (function()
      local wide = "[日本語のリポジトリ - branch]"
      for w = 4, 30 do
        if vim.api.nvim_strwidth(ph.ellipsize(wide, w)) > w then return false end
      end
      return true
    end)())
end

-- ── [5] available_width finds the panel window ──────────────────────────────

print("\n[5] available_width — the panel window's columns, less bufferline's padding")
do
  ok("[5] no panel window -> nil, and heading() then shows everything",
    ph.available_width() == nil, tostring(ph.available_width()))

  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].filetype = "auto-finder"
  vim.cmd("topleft vsplit")
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(w, b)
  vim.api.nvim_win_set_width(w, 38)
  ok("[5] *** a panel window is found by filetype, minus two padding columns ***",
    ph.available_width() == 36, tostring(ph.available_width()))

  -- The config section carries the other filetype, and must match too.
  vim.bo[b].filetype = "auto-finder-config"
  ok("[5] the config section's filetype matches as well",
    ph.available_width() == 36, tostring(ph.available_width()))

  -- A FLOATING window with the panel filetype is not the offset's window:
  -- bufferline matches the top-left window of the layout.
  vim.bo[b].filetype = "nofile-ish"
  local fb = vim.api.nvim_create_buf(false, true)
  vim.bo[fb].filetype = "auto-finder"
  local fw = vim.api.nvim_open_win(fb, false, {
    relative = "editor", row = 2, col = 2, width = 20, height = 5,
  })
  ok("[5] *** a floating panel-filetype window is ignored ***",
    ph.available_width() == nil, tostring(ph.available_width()))
  pcall(vim.api.nvim_win_close, fw, true)
  pcall(vim.api.nvim_win_close, w, true)

  -- text() is what bufferline calls; it must not raise with no panel open.
  local okt, res = pcall(ph.text)
  ok("[5] text() answers even with no panel window",
    okt and type(res) == "string" and res ~= "", tostring(res))
end

package.loaded["utils.scope"] = nil
vim.fn.delete(sb, "rf")
io.stdout:write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail > 0 and 1 or 0)
