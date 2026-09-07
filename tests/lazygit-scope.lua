-- tests/lazygit-scope.lua — `<leader>gg` must open lazygit on the repository
-- you are actually in, and never on a directory that is not a git work tree.
--
-- Johno, 2026-09-07: after `<leader>gw` into `editor/refactor`, `<leader>gg`
-- died with "Error: must be run inside a git repository" (exit 1). Measured in
-- the live session:
--
--   auto-core.git.worktree.get_active()  -> .../nvim-plugins/editor/refactor   correct
--   utils.scope.workspace_root()         -> .../nvim-plugins                   what gg read
--
-- The workspace is a CONTAINER of eleven separate repos, not a repo. It is not
-- a work tree, yet it carries an EMPTY `.git/` directory (created 2026-08-31),
-- so every existence-based check — `vim.fs.find(".git")`, `isdirectory()` —
-- says "repo" while git itself refuses it. `<leader>gw` had already published
-- the right answer into auto-core; `<leader>gg` read the wrong resolver.
--
-- THE PREDICATE THIS SUITE MUST CARRY THROUGH: a candidate can look like a
-- repository and not be one. Section [1] establishes that on the fixture, and
-- every later cell keeps it true while the resolver under test runs — the
-- discipline from `fixture-preconditions-must-survive-the-action`, which was
-- written after a suite proved a hard state in one cell and repaired an easy
-- one in another.
local root = vim.fn.fnamemodify(
  vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h:h"), ":p")

local pass_count, fail_count = 0, 0
local function ok(n, c, d)
  if c then pass_count = pass_count + 1; io.stdout:write("  PASS  " .. n .. "\n")
  else fail_count = fail_count + 1
    io.stdout:write("  FAIL  " .. n .. (d and ("  — " .. tostring(d)) or "") .. "\n") end
  io.stdout:flush()
end

io.stdout:write("lazygit scope — <leader>gg resolves the ACTIVE worktree\n")

package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

-- ── the fixture: the real layout, in miniature ──────────────────────────────
-- ws/                  container, EMPTY .git/  (not a repo — the anomaly)
-- ws/editor/           bare repo               (not a work tree)
-- ws/editor/refactor/  worktree                (the only valid answer)
-- ws/plain/            ordinary repo           (the single-repo common case)
local ws = vim.fn.tempname()
local function sh(cmd)
  local out = vim.fn.system(cmd)
  return vim.v.shell_error == 0, out
end
vim.fn.mkdir(ws .. "/.git", "p")                 -- the empty .git, verbatim
vim.fn.mkdir(ws .. "/seed", "p")
assert(sh({ "git", "-C", ws .. "/seed", "init", "-q", "-b", "main" }))
vim.fn.writefile({ "seed" }, ws .. "/seed/f.txt")
assert(sh({ "git", "-C", ws .. "/seed", "add", "-A" }))
assert(sh({ "git", "-C", ws .. "/seed", "-c", "user.email=t@t", "-c", "user.name=t",
  "commit", "-qm", "seed" }))
assert(sh({ "git", "clone", "-q", "--bare", ws .. "/seed", ws .. "/editor" }))
assert(sh({ "git", "-C", ws .. "/editor", "worktree", "add", "-q",
  ws .. "/editor/refactor", "main" }))
assert(sh({ "git", "clone", "-q", ws .. "/seed", ws .. "/plain" }))

local container = vim.fn.resolve(ws)
local bare      = container .. "/editor"
local worktree  = container .. "/editor/refactor"
local plain     = container .. "/plain"

-- An INDEPENDENT validator, deliberately not the module's own, so a broken
-- module cannot certify itself.
local function is_work_tree(dir)
  local out = vim.fn.system({ "git", "-C", dir, "rev-parse", "--is-inside-work-tree" })
  return vim.v.shell_error == 0 and vim.trim(out) == "true"
end

io.stdout:write("\n[1] the predicate: looking like a repo is not being one\n")
ok("the container HAS a .git entry (so existence checks pass)",
  vim.loop.fs_stat(container .. "/.git") ~= nil)
ok("*** the container is NOT a git work tree ***", is_work_tree(container) == false)
ok("the bare repo is NOT a work tree either", is_work_tree(bare) == false)
ok("the worktree IS a work tree", is_work_tree(worktree) == true)
ok("the plain repo IS a work tree", is_work_tree(plain) == true)

-- ── auto-core stubs. autovim's dependency on auto-core is soft, so the
-- resolver must be exercised with it present, absent, and answering nil. ────
-- Loaded by explicit PATH, never `require`. autovim is config-shaped, so
-- Neovim searches runtimepath before package.path and `require("utils.scope")`
-- silently returns the RUNTIME clone at ~/.config/nvim — which is a different
-- commit and, the first time this suite ran, had no `git_root` at all. The
-- provenance cell below is the guard.
local scope_chunk = assert(loadfile(root .. "lua/utils/scope.lua"))
local function with_auto_core(active, workspace)
  package.loaded["auto-core.git.worktree"] = active ~= false
      and { get_active = function() return active end } or nil
  package.loaded["auto-core.todo.vars"] = workspace ~= false
      and { get = function(n) return n == "WORKSPACE" and workspace or nil end } or nil
  return assert(scope_chunk())
end

io.stdout:write("\n[0] provenance\n")
do
  local probe = with_auto_core(nil, nil)
  local src = debug.getinfo(probe.workspace_root, "S").source:sub(2)
  ok("*** the module under test is THIS worktree's, not ~/.config/nvim ***",
    vim.fn.fnamemodify(src, ":p"):sub(1, #root) == root, src)
end

io.stdout:write("\n[2] the defect, with the predicate still true\n")
local scope = with_auto_core(worktree, container)
ok("workspace_root() still returns the CONTAINER (unchanged for pickers)",
  scope.workspace_root() == container, scope.workspace_root())
ok("*** and the container fails the validator AT THIS MOMENT ***",
  is_work_tree(scope.workspace_root()) == false)
ok("so the pre-fix binding handed lazygit a non-repo — reproduced",
  is_work_tree(scope.workspace_root()) == false)

io.stdout:write("\n[3] the fix: git_root() prefers auto-core's active worktree\n")
ok("git_root exists", type(scope.git_root) == "function")
ok("*** git_root() returns the ACTIVE worktree, not the container ***",
  scope.git_root() == worktree, scope.git_root())
ok("git_root() is a valid work tree", is_work_tree(scope.git_root()) == true)

io.stdout:write("\n[4] every candidate is validated, not trusted\n")
scope = with_auto_core(bare, container)
ok("a BARE active worktree is rejected", scope.git_root() ~= bare, scope.git_root())
scope = with_auto_core(container, container)
ok("an active worktree that is the bogus container is rejected",
  scope.git_root() ~= container, scope.git_root())
scope = with_auto_core(container .. "/gone", container)
ok("a deleted/stale active worktree is rejected",
  scope.git_root() ~= container .. "/gone", scope.git_root())
scope = with_auto_core("", container)
ok("an empty-string active worktree is rejected", scope.git_root() ~= "", scope.git_root())

io.stdout:write("\n[5] fallback order, when auto-core has no active worktree yet\n")
-- `_active_worktree` starts nil and is only set by the first
-- `worktree:switched` event, so `<leader>gg` before any `<leader>gw` must
-- still work. cwd is the next best answer: it is user-controlled and does not
-- follow the focused buffer, which is the property scope.lua exists to protect.
local prev_cwd = vim.fn.getcwd()
vim.cmd.cd(plain)
scope = with_auto_core(nil, container)
ok("*** nil active -> the work tree containing cwd ***",
  scope.git_root() == vim.fn.resolve(plain), scope.git_root())
vim.cmd.cd(worktree)
ok("...and it follows cwd, resolved per call",
  with_auto_core(nil, container).git_root() == worktree)
vim.cmd.cd(prev_cwd)

io.stdout:write("\n[6] auto-core absent entirely (soft dependency)\n")
vim.cmd.cd(plain)
scope = with_auto_core(false, false)
ok("git_root() still answers with no auto-core at all",
  scope.git_root() == vim.fn.resolve(plain), scope.git_root())
ok("workspace_root() falls back to cwd, as before",
  scope.workspace_root() == vim.fn.getcwd(), scope.workspace_root())
vim.cmd.cd(prev_cwd)

io.stdout:write("\n[7] the property, over every candidate shape\n")
-- Not "does it pick the right one" but "can it EVER return a non-repo".
local returned_non_repo = {}
for _, active in ipairs({ worktree, bare, container, container .. "/gone", "" }) do
  vim.cmd.cd(worktree)
  local s = with_auto_core(active, container)
  local got = s.git_root()
  if got ~= nil and not is_work_tree(got) then
    returned_non_repo[#returned_non_repo + 1] = tostring(active) .. " -> " .. tostring(got)
  end
end
vim.cmd.cd(prev_cwd)
ok("*** git_root() never returns a non-work-tree ***", #returned_non_repo == 0,
  table.concat(returned_non_repo, "; "))

io.stdout:write("\n[8] negative controls\n")
-- N1: the validator must not be satisfiable by a .git ENTRY, which is the
-- exact mistake `vim.fs.find(".git")` makes and the reason this bug existed.
ok("N1: an empty .git/ does not satisfy the validator",
  is_work_tree(container) == false and vim.loop.fs_stat(container .. "/.git") ~= nil)
-- N2: the fixture must be capable of failing. If the validator said true for
-- everything, every cell above would pass while proving nothing.
ok("N2: the validator rejects a plain non-repo directory",
  is_work_tree(vim.fn.fnamemodify(ws, ":h")) == false or
  is_work_tree(container .. "/seed/../.." ) == false)
-- N3: git_root and workspace_root must be able to DISAGREE, or [3] is vacuous.
scope = with_auto_core(worktree, container)
ok("N3: git_root() and workspace_root() genuinely differ here",
  scope.git_root() ~= scope.workspace_root())

io.stdout:write("\n[9] the wiring, so a revert cannot pass silently\n")
-- A text assertion, named honestly as one: loading config/keymaps.lua needs
-- Snacks and the full nav modal, so the binding is pinned by source instead.
local km = table.concat(vim.fn.readfile(root .. "lua/config/keymaps.lua"), "\n")
-- Anchor on the keymap CALL, not the first mention of the lhs: the comment
-- above it names `workspace_root()` as the thing that broke, and a match that
-- swept the comment in would fail on the explanation rather than the code.
local gg = km:match('vim%.keymap%.set%("n",%s*"<leader>gg".-desc%s*=%s*"[^"]*"')
ok("<leader>gg is still bound in config/keymaps.lua", gg ~= nil)
ok("*** <leader>gg calls git_root(), not workspace_root() ***",
  gg ~= nil and gg:find("git_root", 1, true) ~= nil
    and gg:find("workspace_root", 1, true) == nil, gg)

vim.fn.delete(ws, "rf")
io.stdout:write(("\n%d passed, %d failed\n"):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
