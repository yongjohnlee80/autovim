-- Picker search scope — pin to the workspace, not to the focused buffer's repo.
--
-- LazyVim binds its "Root Dir" pickers (`<leader><space>`, `<leader>ff`,
-- `<leader>/`, `<leader>sg`, `<leader>sw`) to `LazyVim.pick(cmd)`, which
-- resolves the search root from the CURRENT BUFFER via `LazyVim.root()`
-- (lsp workspace → `.git`/`lua` walk-up → cwd).
--
-- That is the wrong scope in an auto-agents session. The knowledge base
-- (`$KB_ROOT`, e.g. `~/.config/nvim/.auto-agents-config/kb`) is its own git
-- repo, so the moment a KB document becomes the focused buffer — an agent
-- opening a `.todo-list/` task, an ADR, an md-harpoon preview — the `.git`
-- walk-up stops inside the KB and every one of those keymaps silently
-- narrows to it. The project's files simply stop showing up, with no
-- indication why.
--
-- Fix: resolve the scope ourselves and pass an explicit `cwd`, which makes
-- `LazyVim.pick.open` skip root detection entirely (see
-- `lazyvim/util/pick.lua`: `if not opts.cwd and opts.root ~= false then
-- opts.cwd = LazyVim.root(...)`). The values come from auto-core's canonical
-- `$WORKSPACE` / `$KB_ROOT` built-ins (`auto-core.todo.vars`) — the same
-- resolvers the todo store uses when it writes portable task refs, so search
-- scope and task refs can never disagree.
--
-- Resolution runs per keypress rather than at spec-eval time, so switching
-- worktrees mid-session moves the scope with it.
--
-- Deliberately untouched: LazyVim's cwd-scoped siblings (`<leader>fF`,
-- `<leader>sG`, `<leader>sW`) and the `<a-c>` toggle inside an open picker,
-- which still swaps between the buffer's root dir and cwd on demand.

---Resolve one of auto-core's built-in path variables. Soft dependency —
---autovim must stay usable when auto-core is absent or not yet loaded.
---@param name string  `"WORKSPACE"` or `"KB_ROOT"`
---@return string?
local function auto_core_var(name)
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

---The workspace root, falling back to cwd when auto-core can't answer.
---@return string
local function workspace_root()
  return auto_core_var("WORKSPACE") or vim.fn.getcwd()
end

---Picker entry pinned to the workspace root.
---@param command string  a `LazyVim.pick` command name
---@return fun()
local function pick_workspace(command)
  return function()
    LazyVim.pick.open(command, { cwd = workspace_root() })
  end
end

---Picker entry pinned to the knowledge-base root.
---@param command string  a `LazyVim.pick` command name
---@return fun()
local function pick_kb(command)
  return function()
    local root = auto_core_var("KB_ROOT")
    if not root then
      LazyVim.warn(
        "No knowledge base root resolved.\n"
          .. "`$AUTO_AGENTS_KB_ROOT` is unset and `auto-agents.kb.root()` returned nothing.",
        { title = "Search (KB Root)" }
      )
      return
    end
    LazyVim.pick.open(command, { cwd = root })
  end
end

return {
  {
    "folke/snacks.nvim",
    -- stylua: ignore
    keys = {
      -- Workspace-pinned replacements for LazyVim's "Root Dir" pickers.
      { "<leader><space>", pick_workspace("files"),     desc = "Find Files (Workspace)" },
      { "<leader>ff",      pick_workspace("files"),     desc = "Find Files (Workspace)" },
      { "<leader>/",       pick_workspace("live_grep"), desc = "Grep (Workspace)" },
      { "<leader>sg",      pick_workspace("live_grep"), desc = "Grep (Workspace)" },
      { "<leader>sw",      pick_workspace("grep_word"), desc = "Visual selection or word (Workspace)", mode = { "n", "x" } },
      -- Knowledge base, addressed explicitly.
      { "<leader>fK",      pick_kb("files"),            desc = "Find Files (KB Root)" },
      { "<leader>sK",      pick_kb("live_grep"),        desc = "Grep (KB Root)" },
    },
  },
}
