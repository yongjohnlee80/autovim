-- Where "the project" is, for anything that must not follow the focused buffer.
--
-- The recurring bug this exists to prevent: several LazyVim entry points
-- resolve their root from the CURRENT BUFFER (`LazyVim.root()`,
-- `LazyVim.root.git()`, which walk up for `.git`). The knowledge base is its own
-- git repo, so the moment a KB document becomes the focused buffer — an agent
-- opening a `.todo-list/` task, an ADR, an md-harpoon preview — that walk-up
-- stops inside the KB and the feature silently retargets there. It has now bitten
-- the Root-Dir pickers (`<leader><space>`, `<leader>ff`, `<leader>/`, …) and
-- lazygit (`<leader>gg`), which is the tell that it belongs in one place rather
-- than being re-fixed per feature.
--
-- Values come from auto-core's canonical `$WORKSPACE` / `$KB_ROOT` built-ins —
-- the same resolvers the todo store uses when it writes portable task refs, so
-- search scope, git scope and task refs cannot disagree.
--
-- Resolution is per CALL, never cached at spec-eval time, so switching
-- worktrees mid-session moves the scope with it.

local M = {}

---Resolve one of auto-core's built-in path variables. Soft dependency —
---AutoVim must stay usable when auto-core is absent or not yet loaded.
---@param name string  `"WORKSPACE"` or `"KB_ROOT"`
---@return string?
function M.auto_core_var(name)
  local ok, vars = pcall(require, "auto-core.todo.vars")
  if not ok then
    return nil
  end
  local ok_value, value = pcall(vars.get, name)
  if ok_value and type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

---The workspace root, falling back to cwd when auto-core cannot answer.
---@return string
function M.workspace_root()
  return M.auto_core_var("WORKSPACE") or vim.fn.getcwd()
end

---The knowledge-base root, or nil.
---@return string?
function M.kb_root()
  return M.auto_core_var("KB_ROOT")
end

---The worktree `<leader>gw` last switched to, as auto-core recorded it.
---
---`worktree.nvim`'s deliberate switch paths publish `worktree:switched` and
---call `auto-core.git.worktree.set_active()`; an arbitrary `:cd` does not. So
---this is the session's answer to "which checkout am I working in", and it is
---already correct — see `git_root()` for why that mattered.
---
---Soft dependency, like every other auto-core reach here: nil when auto-core
---is absent, or before the first switch of the session (`_active_worktree`
---starts nil and is only set by that event).
---@return string?
function M.active_worktree()
  local ok, wt = pcall(require, "auto-core.git.worktree")
  if not ok or type(wt) ~= "table" or type(wt.get_active) ~= "function" then
    return nil
  end
  local ok_value, value = pcall(wt.get_active)
  if ok_value and type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

---Resolve `dir` to the top of its git WORK TREE, or nil.
---
---The validation is the point. A directory can carry a `.git` entry and not be
---a repository: this workspace has an empty `.git/` at its root, so
---`vim.fs.find(".git")`, `isdirectory()` and every other existence check call
---it a repo while git refuses it. A bare repo fails the same way.
---
---`rev-parse --show-toplevel` answers every case with its EXIT CODE, which is
---why it is the whole check. Measured against git 2.51:
---
---  a work tree (a bare repo's worktrees included)  rc 0    prints the top
---  a bare repo root                                rc 128  "must be run in a work tree"
---  inside a `.git` directory                       rc 128  same
---  an empty `.git/` container, or a plain dir      rc 128  "not a git repository"
---
---An earlier draft also asked `--is-inside-work-tree` and required it to print
---`true`. That check could never fire, because `--show-toplevel` already fails
---whenever the answer would be `false` — and mutation proved it: removing
---either check ALONE left the suite green, each masking the other, while
---removing both reddened three cells. An unfalsifiable guard reports clean, so
---it is gone.
---@param dir string?
---@return string?
local function work_tree_top(dir)
  if type(dir) ~= "string" or dir == "" then return nil end
  if vim.fn.isdirectory(dir) ~= 1 then return nil end
  local out = vim.fn.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then return nil end
  local top = vim.trim(out)
  return top ~= "" and top or nil
end

---The git scope: the repository a git-scoped entry point should act on.
---
---Johno, 2026-09-07: after `<leader>gw` into `editor/refactor`, `<leader>gg`
---died with "must be run inside a git repository". It was passing
---`workspace_root()`, and this workspace is a CONTAINER of eleven separate
---repos — several of them bare with their worktrees nested inside. A container
---of repos is not a repo, so there was no value of `WORKSPACE` that could have
---worked here.
---
---`<leader>gw` had already published the right answer into auto-core; nothing
---read it. Hence the order:
---
---  1. auto-core's ACTIVE WORKTREE — what the last deliberate switch set.
---  2. the work tree containing CWD — user-controlled, and still does not
---     follow the focused buffer, which is the property this module exists to
---     protect.
---  3. nil — say so, rather than launching a tool into a failure.
---
---`workspace_root()` is deliberately NOT a fallback: it is the search scope,
---and returning it here is how the outage happened. Every candidate is
---validated, so this never returns a directory git would reject.
---@return string?
function M.git_root()
  return work_tree_top(M.active_worktree()) or work_tree_top(vim.fn.getcwd())
end

return M
