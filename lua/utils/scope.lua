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

return M
