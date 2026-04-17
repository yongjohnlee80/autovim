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

local M = {}

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

local function switch_to(path)
  local target = norm(path)
  vim.cmd.cd(vim.fn.fnameescape(target))
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
  vim.notify(
    ("worktree ← root (%s)"):format(root),
    vim.log.levels.INFO,
    { title = "worktree" }
  )
end

return M
