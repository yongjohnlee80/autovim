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
  -- Plain `Neotree dir=<path>` re-roots the existing source; `action=show`
  -- short-circuits when the window is already visible and skips re-navigation.
  local ok = pcall(vim.cmd, "Neotree dir=" .. cwd)
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

local function git_common_dir(path)
  local out = vim.fn.systemlist({
    "git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir",
  })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == "" then return nil end
  return (out[1]:gsub("/$", ""))
end

-- New worktrees are created as siblings of the common git dir.
--   /foo/repo/.bare  → container /foo/repo   → new wt at /foo/repo/<name>
--   /foo/repo/.git   → container /foo/repo   → new wt at /foo/repo/<name>
--   /foo/repo.git    → container /foo        → new wt at /foo/<name>
local function repo_container(common)
  return vim.fn.fnamemodify(common, ":h")
end

local function list_child_repos(dir)
  local repos = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return repos end
  while true do
    local name, t = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if (t == "directory" or t == "link") and not name:match("^%.") then
      local full = dir .. "/" .. name
      if is_git(full) then
        table.insert(repos, { name = name, path = norm(full) })
      end
    end
  end
  table.sort(repos, function(a, b) return a.name < b.name end)
  return repos
end

local function list_branches(repo_path)
  local lines = vim.fn.systemlist({
    "git", "-C", repo_path, "for-each-ref", "--format=%(refname:short)", "refs/heads",
  })
  if vim.v.shell_error ~= 0 then return {} end
  -- Float main/master to the top so the first choice is usually right.
  table.sort(lines, function(a, b)
    local function rank(s)
      if s == "main" then return 0 end
      if s == "master" then return 1 end
      return 2
    end
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return lines
end

local function has_uncommitted(worktree_path)
  local lines =
    vim.fn.systemlist({ "git", "-C", worktree_path, "status", "--porcelain" })
  return vim.v.shell_error == 0 and #lines > 0
end

-- Any buffer under `path` (inclusive) passed to `fn`. Matching is done on
-- fully-resolved absolute paths so that relative-named buffers line up too.
local function each_buf_under(path, fn)
  local prefix = path .. "/"
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        local abs = norm(name)
        if abs == path or abs:sub(1, #prefix) == prefix then
          fn(buf, abs)
        end
      end
    end
  end
end

-- Dirty buffers inside `path`. `git status` only knows what's on disk, so
-- we separately check nvim's in-memory modified flag to avoid silently
-- nuking unsaved edits when the worktree gets removed.
local function modified_buffers_under(path)
  local dirty = {}
  each_buf_under(path, function(buf, abs)
    if vim.bo[buf].modified then table.insert(dirty, abs) end
  end)
  return dirty
end

-- Force-close every buffer whose file used to live inside the (now-removed)
-- worktree. Without this the buffers linger, point at missing files, and
-- explode on focus/save.
local function wipe_buffers_under(path)
  local count = 0
  each_buf_under(path, function(buf)
    if pcall(vim.api.nvim_buf_delete, buf, { force = true }) then
      count = count + 1
    end
  end)
  return count
end

local function run_git(args)
  local res = vim.system(args, { text = true }):wait()
  return res.code, (res.stdout or "") .. (res.stderr or "")
end

function M.add()
  local cwd = norm(vim.fn.getcwd())
  local here_common = git_common_dir(cwd)

  local function proceed(repo_common, label)
    local container = repo_container(repo_common)

    vim.ui.input({ prompt = ("New worktree in %s: "):format(label) }, function(name)
      if not name then return end
      name = vim.trim(name)
      if name == "" then return end

      local branches = list_branches(repo_common)
      if #branches == 0 then
        vim.notify(
          "No branches found in repo",
          vim.log.levels.ERROR,
          { title = "worktree" }
        )
        return
      end

      vim.ui.select(branches, {
        prompt = ("Base branch for '%s':"):format(name),
      }, function(base)
        if not base then return end
        local target = container .. "/" .. name
        local code, out = run_git({
          "git", "-C", repo_common, "worktree", "add", "-b", name, target, base,
        })
        if code ~= 0 then
          vim.notify(
            "git worktree add failed:\n" .. out,
            vim.log.levels.ERROR,
            { title = "worktree" }
          )
          return
        end
        refresh_file_tree()
        vim.notify(
          ("+ %s (from %s)"):format(relative_to_root(target), base),
          vim.log.levels.INFO,
          { title = "worktree" }
        )
      end)
    end)
  end

  if here_common then
    proceed(here_common, vim.fn.fnamemodify(repo_container(here_common), ":t"))
    return
  end

  -- At the root: scan child dirs for repos and let the user pick one.
  local repos = list_child_repos(root)
  if #repos == 0 then
    vim.notify(
      ("no repos found under %s"):format(root),
      vim.log.levels.WARN,
      { title = "worktree" }
    )
    return
  end
  vim.ui.select(repos, {
    prompt = "Select a repo:",
    format_item = function(r) return r.name end,
  }, function(choice)
    if not choice then return end
    local repo_common = git_common_dir(choice.path)
    if not repo_common then
      vim.notify(
        "Could not resolve git-common-dir for " .. choice.path,
        vim.log.levels.ERROR,
        { title = "worktree" }
      )
      return
    end
    proceed(repo_common, choice.name)
  end)
end

function M.remove()
  local cwd = norm(vim.fn.getcwd())
  local here_common = git_common_dir(cwd)

  local candidates = {}
  if here_common then
    local lines =
      vim.fn.systemlist({ "git", "-C", here_common, "worktree", "list", "--porcelain" })
    if vim.v.shell_error == 0 then
      for _, wt in ipairs(parse_porcelain(lines)) do
        if not wt.bare then
          wt.path = norm(wt.path)
          table.insert(candidates, wt)
        end
      end
    end
  else
    candidates = collect_worktrees(root)
  end

  -- Don't offer the active worktree — removing it while we stand on it is a
  -- foot-gun (`git worktree remove` refuses, and we'd need to cd away first).
  local removable = {}
  for _, wt in ipairs(candidates) do
    if wt.path ~= cwd then table.insert(removable, wt) end
  end

  if #removable == 0 then
    vim.notify(
      "no removable worktrees found",
      vim.log.levels.WARN,
      { title = "worktree" }
    )
    return
  end

  vim.ui.select(removable, {
    prompt = "Remove worktree:",
    format_item = function(wt)
      local rel = relative_to_root(wt.path)
      local branch = wt.branch and ("[" .. wt.branch .. "]")
        or wt.detached and "[detached]"
        or ""
      return ("%-40s %s"):format(rel, branch)
    end,
  }, function(choice)
    if not choice then return end
    if has_uncommitted(choice.path) then
      vim.notify(
        ("refusing to remove — uncommitted changes in %s"):format(
          relative_to_root(choice.path)
        ),
        vim.log.levels.ERROR,
        { title = "worktree" }
      )
      return
    end
    local dirty = modified_buffers_under(choice.path)
    if #dirty > 0 then
      vim.notify(
        ("refusing to remove — unsaved buffers in %s:\n  %s"):format(
          relative_to_root(choice.path),
          table.concat(dirty, "\n  ")
        ),
        vim.log.levels.ERROR,
        { title = "worktree" }
      )
      return
    end
    -- Capture the repo's common dir BEFORE removing the worktree, since
    -- after removal `choice.path` is gone and can't anchor a `-C` call.
    local repo_common = git_common_dir(choice.path)

    local code, out =
      run_git({ "git", "-C", choice.path, "worktree", "remove", choice.path })
    if code ~= 0 then
      vim.notify(
        "git worktree remove failed:\n" .. out,
        vim.log.levels.ERROR,
        { title = "worktree" }
      )
      return
    end
    local wiped = wipe_buffers_under(choice.path)
    refresh_file_tree()
    vim.notify(
      ("- %s%s"):format(
        relative_to_root(choice.path),
        wiped > 0 and (" (closed %d buffer(s))"):format(wiped) or ""
      ),
      vim.log.levels.INFO,
      { title = "worktree" }
    )

    -- Worktree is gone; optionally clean up the branch too. Detached HEADs
    -- have no branch to delete, so skip the prompt in that case.
    if not choice.branch or not repo_common then return end
    local answer = vim.fn.confirm(
      ("Also delete branch '%s'?"):format(choice.branch),
      "&Yes\n&No",
      2
    )
    if answer ~= 1 then return end
    local bcode, bout =
      run_git({ "git", "-C", repo_common, "branch", "-D", choice.branch })
    if bcode ~= 0 then
      vim.notify(
        "git branch -D failed:\n" .. bout,
        vim.log.levels.ERROR,
        { title = "worktree" }
      )
      return
    end
    vim.notify(
      ("- branch %s"):format(choice.branch),
      vim.log.levels.INFO,
      { title = "worktree" }
    )
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
