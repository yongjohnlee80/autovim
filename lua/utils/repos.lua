-- Registered repos: a small JSON-backed list of repo paths consumed by the
-- neo-tree-workspace source. Add/remove with :RepoRegister / :RepoUnregister.

local M = {}

local registry_file = vim.fn.stdpath("data") .. "/registered-repos.json"

local function read_json(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  if content == "" then return {} end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

local function write_json(path, data)
  local f, err = io.open(path, "w")
  if not f then
    vim.notify("repos: cannot write " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  f:write(vim.json.encode(data))
  f:close()
  return true
end

local function normalize(p)
  return vim.fn.fnamemodify(vim.fn.expand(p), ":p"):gsub("/$", "")
end

function M.load()
  local data = read_json(registry_file)
  local seen, out = {}, {}
  for _, p in ipairs(data) do
    if type(p) == "string" and p ~= "" and not seen[p] then
      seen[p] = true
      table.insert(out, p)
    end
  end
  return out
end

function M.save(repos)
  return write_json(registry_file, repos)
end

local function resolve_repo_root(path)
  local toplevel = vim.fn.systemlist({ "git", "-C", path, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and toplevel[1] and toplevel[1] ~= "" then
    return toplevel[1]
  end
  if vim.fn.isdirectory(path .. "/.git") == 1 then
    local out = vim.fn.systemlist({ "git", "--git-dir=" .. path .. "/.git", "rev-parse", "--is-bare-repository" })
    if vim.v.shell_error == 0 and out[1] == "true" then
      return path
    end
  end
  return nil
end

local function notify_workspace_changed()
  local ok, ws = pcall(require, "neo-tree-workspace")
  if ok and ws.on_registry_changed then
    ws.on_registry_changed()
  end
end

function M.add(path)
  path = normalize(path or vim.fn.getcwd())
  if vim.fn.isdirectory(path) == 0 then
    vim.notify("repos: not a directory: " .. path, vim.log.levels.ERROR)
    return false
  end
  local root = resolve_repo_root(path)
  if not root then
    vim.notify("repos: not a git repo or worktree-bare layout: " .. path, vim.log.levels.ERROR)
    return false
  end
  root = normalize(root)
  local repos = M.load()
  for _, p in ipairs(repos) do
    if p == root then
      vim.notify("repos: already registered: " .. root, vim.log.levels.WARN)
      return false
    end
  end
  table.insert(repos, root)
  M.save(repos)
  notify_workspace_changed()
  vim.notify("repos: registered " .. root)
  return true
end

function M.remove(path)
  path = normalize(path)
  local repos = M.load()
  local out, removed = {}, false
  for _, p in ipairs(repos) do
    if p == path then
      removed = true
    else
      table.insert(out, p)
    end
  end
  if removed then
    M.save(out)
    notify_workspace_changed()
    vim.notify("repos: unregistered " .. path)
  else
    vim.notify("repos: not in registry: " .. path, vim.log.levels.WARN)
  end
  return removed
end

return M
