-- Switch Neovim's cwd between git repos (and their worktrees) that live
-- as children of the directory nvim was originally opened in.
--
-- For every child directory that looks git-managed we shell out to
-- `git worktree list --porcelain` and flatten all discovered worktrees
-- into a single picker list. Bare repos themselves are omitted (you
-- don't cd into a bare), but all their worktrees are listed.
--
-- Existing :term buffers keep their own pwd (they're independent child
-- processes that inherited cwd at spawn time). Only new terminals and
-- new file-pickers pick up the switched cwd.
--
-- LSP note: language servers that anchor their workspace to a go.mod /
-- project root (e.g. gopls) cache that root at first attach, so a plain
-- :cd leaves them pointing at the old worktree. After each cd we stop
-- the configured servers and re-fire FileType autocmds on every loaded
-- buffer so lspconfig re-resolves root_dir against the new cwd.

local M = {}

-- LSP servers that are workspace-rooted and need a full restart on cd.
-- Add more here if another server starts mis-resolving after switches.
M.lsp_servers_to_restart = { "gopls" }

-- Captured once when this module is first required (keymaps.lua requires
-- it at startup). Use set_root() to override.
local root = vim.fn.getcwd(-1, -1)

local function norm(path)
  return (vim.fn.fnamemodify(path, ":p"):gsub("/$", ""))
end

function M.set_root(path)
  root = norm(path)
end

function M.get_root()
  return root
end

local function is_git(path)
  -- `.git` as directory (regular repo / bare) OR file (linked worktree).
  return vim.fn.isdirectory(path .. "/.git") == 1
    or vim.fn.filereadable(path .. "/.git") == 1
end

-- Parse `git worktree list --porcelain` output into a list of
-- { path, branch?, head?, bare?, detached? } records.
local function parse_porcelain(lines)
  local out, cur = {}, nil
  local function flush()
    if cur and cur.path then table.insert(out, cur) end
    cur = nil
  end
  for _, line in ipairs(lines) do
    if line:match("^worktree ") then
      flush()
      cur = { path = line:sub(10) }
    elseif cur then
      local branch = line:match("^branch (.+)$")
      if branch then
        cur.branch = branch:gsub("^refs/heads/", "")
      elseif line:match("^HEAD ") then
        cur.head = line:sub(6, 13)
      elseif line == "bare" then
        cur.bare = true
      elseif line == "detached" then
        cur.detached = true
      end
    end
  end
  flush()
  return out
end

local function collect_worktrees(dir)
  local seen, out = {}, {}

  local handle = vim.uv.fs_scandir(dir)
  if not handle then return out end

  while true do
    local name, t = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if (t == "directory" or t == "link") and not name:match("^%.") then
      local full = dir .. "/" .. name
      if is_git(full) then
        local lines =
          vim.fn.systemlist({ "git", "-C", full, "worktree", "list", "--porcelain" })
        if vim.v.shell_error == 0 then
          for _, wt in ipairs(parse_porcelain(lines)) do
            if not wt.bare then
              wt.path = norm(wt.path)
              if not seen[wt.path] then
                seen[wt.path] = true
                table.insert(out, wt)
              end
            end
          end
        else
          -- Not a valid repo but .git entry exists — include as-is.
          local p = norm(full)
          if not seen[p] then
            seen[p] = true
            table.insert(out, { path = p })
          end
        end
      end
    end
  end

  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

local function relative_to_root(path)
  local p, r = norm(path), norm(root)
  if p == r then return "." end
  if p:sub(1, #r + 1) == r .. "/" then return p:sub(#r + 2) end
  return p
end

-- If a neo-tree filesystem window is currently visible, re-anchor it at
-- the new cwd so the file tree reflects the worktree we just switched
-- into. No-op if neo-tree isn't installed or isn't on screen — we don't
-- want the switch to *open* neo-tree when the user hasn't asked for it.
local function refresh_file_tree()
  local mgr_ok, manager = pcall(require, "neo-tree.sources.manager")
  if not mgr_ok then return end

  local state = manager.get_state and manager.get_state("filesystem")
  if not (state and state.winid and vim.api.nvim_win_is_valid(state.winid)) then
    return
  end

  local cwd = vim.fn.fnameescape(vim.fn.getcwd())
  local ok = pcall(vim.cmd, "Neotree action=show dir=" .. cwd)
  if not ok then
    pcall(manager.refresh, "filesystem")
  end
end

-- Stop workspace-rooted LSP clients and re-fire FileType on every loaded
-- buffer so lspconfig's attach logic runs again with the new cwd as the
-- root-resolution anchor. Buffers whose path still lies inside an old
-- worktree will re-anchor to *their own* go.mod — which is correct; we
-- just need gopls to stop reusing whichever workspace it picked first.
local function restart_workspace_lsps()
  local stopped = 0
  for _, name in ipairs(M.lsp_servers_to_restart) do
    for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
      vim.lsp.stop_client(client.id, true)
      stopped = stopped + 1
    end
  end
  if stopped == 0 then return end

  -- Stop is async; defer re-attach so the old client is fully gone
  -- before lspconfig's autocmd fires a new launch.
  --
  -- nvim_exec_autocmds disallows both `buffer` and `pattern` on one call
  -- (they're mutually exclusive). Pass `buffer` only — nvim uses the
  -- buffer's own filetype to match pattern-based autocmds, which is the
  -- shape lspconfig registers. Wrap in pcall so one unhealthy buffer
  -- doesn't abort the rest of the re-attach loop.
  vim.defer_fn(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" then
        local ft = vim.bo[bufnr].filetype
        if ft ~= "" then
          pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = bufnr })
        end
      end
    end
  end, 150)
end

local function switch_to(path)
  local target = norm(path)
  vim.cmd.cd(vim.fn.fnameescape(target))
  restart_workspace_lsps()
  refresh_file_tree()
  vim.notify(
    ("worktree → %s"):format(relative_to_root(target)),
    vim.log.levels.INFO,
    { title = "worktree" }
  )
end

function M.pick()
  local worktrees = collect_worktrees(root)
  if #worktrees == 0 then
    vim.notify(
      ("no worktrees found under %s"):format(root),
      vim.log.levels.WARN,
      { title = "worktree" }
    )
    return
  end

  local cwd = norm(vim.fn.getcwd())
  vim.ui.select(worktrees, {
    prompt = "Switch worktree:",
    format_item = function(wt)
      local rel = relative_to_root(wt.path)
      local branch = wt.branch and ("[" .. wt.branch .. "]")
        or wt.detached and "[detached]"
        or ""
      local marker = wt.path == cwd and "●" or " "
      return ("%s %-40s %s"):format(marker, rel, branch)
    end,
  }, function(choice)
    if choice then switch_to(choice.path) end
  end)
end

function M.home()
  if norm(vim.fn.getcwd()) == norm(root) then
    vim.notify(
      ("already at root: %s"):format(root),
      vim.log.levels.INFO,
      { title = "worktree" }
    )
    return
  end
  vim.cmd.cd(vim.fn.fnameescape(root))
  restart_workspace_lsps()
  refresh_file_tree()
  vim.notify(
    ("worktree ← root (%s)"):format(root),
    vim.log.levels.INFO,
    { title = "worktree" }
  )
end

return M
