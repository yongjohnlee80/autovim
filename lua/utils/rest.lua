-- Scaffolding and helpers for kulala.nvim `.http` collections.
--
-- Project layout created under <project>/.rest/:
--
--   .rest/
--     http/
--       generated/                    -- auto-generated (openapi-v3.yaml, routes, ...)
--       local/                        -- human-authored .http files
--     http-client.private.env.json    -- GITIGNORED; single env file
--     .gitignore
--     README.md
--
-- Single env file keeps every project predictable: one env named `dev`
-- holding the generic keys every app in this setup uses.

local M = {}

local DEFAULT_ENV_NAME = "dev"
local ENV_FILE = "http-client.private.env.json"

local GITIGNORE = [[
# Kulala env (holds USER_PASS / API_KEY); never commit
http-client.private.env.json
*.private.env.json

# Saved response dumps
**/*.response
**/*.response.json

# Cached env-target pick (per-project, set by :RestEnvSelect / generate-http skill)
.generate-http.conf
]]

local PRIVATE_ENV = [[
{
  "dev": {
    "BASE_URL": "http://localhost:8080",
    "USER_NAME": "",
    "USER_PASS": "",
    "API_KEY": ""
  }
}
]]

local SCRATCH_HTTP = [[
### Scratch request

GET {{BASE_URL}}/healthz
Accept: application/json

###

### Authenticated request

GET {{BASE_URL}}/me
Authorization: Bearer {{API_KEY}}
Accept: application/json

###
]]

local README = [[
# .rest

Per-project HTTP request collection consumed by `kulala.nvim`.

## Layout

- `http/generated/` - auto-generated from `openapi-v3.yaml` or route sources.
  Treat as disposable; regenerate instead of hand-editing.
- `http/local/` - human-authored `.http` files for ad-hoc and exploratory requests.
- `http-client.private.env.json` - the single env file. **Gitignored.**

## Env convention

One env named `dev` holds the keys every app in this setup uses:

    BASE_URL   USER_NAME   USER_PASS   API_KEY

Fill in the values you need; leave the rest empty. The env is selected
automatically on `:RestScaffold` and re-applied on `BufEnter` for any
`.http` file under this project.

To switch envs at runtime:

    :lua require('kulala').set_selected_env('dev')

## Running a request

Place the cursor inside a request block and run `<leader>Rr`. `<leader>Rl`
replays the last request. `<leader>Ra` runs every request in the buffer.
`<leader>Rt` toggles between body and headers view.

## Dependencies

`kulala.nvim` needs only `curl` and Neovim 0.10+ (tree-sitter is built-in).
Optional CLIs: `jq` (JSON), `xmllint` (XML), `grpcurl` (gRPC), `websocat` (WS).
]]

-- --------------------------------------------------------------------------
-- Low-level fs helpers
-- --------------------------------------------------------------------------

local function write_if_missing(path, contents)
  if vim.uv.fs_stat(path) then
    return false
  end
  local fd, err = vim.uv.fs_open(path, "w", tonumber("644", 8))
  if not fd then
    vim.notify("rest: failed to open " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  vim.uv.fs_write(fd, contents, 0)
  vim.uv.fs_close(fd)
  return true
end

local function mkdir_p(path)
  vim.fn.mkdir(path, "p")
end

-- --------------------------------------------------------------------------
-- Root resolution
-- --------------------------------------------------------------------------

-- Walk up from `start` looking for an existing `.rest/` directory. Stops at
-- $HOME or filesystem root. Returns the containing directory (the one that
-- has `.rest/` inside it), or nil if none found.
local function find_existing_rest_up(start)
  local dir = start
  if not dir or dir == "" then
    dir = vim.fn.expand("%:p:h")
  end
  if not dir or dir == "" or dir == "." then
    dir = vim.fn.getcwd()
  end
  local home = vim.fn.expand("~")
  while dir and dir ~= "" and dir ~= "/" do
    if vim.uv.fs_stat(dir .. "/.rest") then
      return dir
    end
    if dir == home then break end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end
  return nil
end

-- Where a FRESH `.rest/` scaffold should be created when none exists
-- upstream. Prefers the bare-git parent so one `.rest/` serves every worktree.
local function scaffold_root()
  local wt_lines = vim.fn.systemlist({ "git", "worktree", "list" })
  if vim.v.shell_error == 0 then
    for _, line in ipairs(wt_lines) do
      local path = line:match("^(%S+)%s+%S+%s+%(bare%)$")
      if path and path ~= "" then
        return path
      end
    end
  end
  local ok, lv = pcall(require, "lazyvim.util")
  if ok and type(lv.root) == "function" then
    local r = lv.root()
    if type(r) == "string" and r ~= "" then
      return r
    end
  end
  local top = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and top[1] and top[1] ~= "" then
    return top[1]
  end
  return vim.fn.getcwd()
end

function M.root()
  local existing = find_existing_rest_up()
  if existing then
    return existing .. "/.rest"
  end
  return scaffold_root() .. "/.rest"
end

-- --------------------------------------------------------------------------
-- Cache (shared with the `generate-http` Claude skill)
-- --------------------------------------------------------------------------

local CACHE_FILE = ".generate-http.conf"
local CACHE_KEY = "env_name"

local function cache_path()
  return M.root() .. "/" .. CACHE_FILE
end

local function read_cache()
  local path = cache_path()
  if not vim.uv.fs_stat(path) then return {} end
  local out = {}
  for line in io.lines(path) do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k then out[k] = v end
  end
  return out
end

local function write_cache(tbl)
  local path = cache_path()
  local fd = vim.uv.fs_open(path, "w", tonumber("644", 8))
  if not fd then return end
  local parts = {}
  for k, v in pairs(tbl) do table.insert(parts, k .. "=" .. v) end
  table.sort(parts)
  vim.uv.fs_write(fd, table.concat(parts, "\n") .. "\n", 0)
  vim.uv.fs_close(fd)
end

-- --------------------------------------------------------------------------
-- Env helpers
-- --------------------------------------------------------------------------

local function env_file_path()
  return M.root() .. "/" .. ENV_FILE
end

local function list_env_names()
  local path = env_file_path()
  if not vim.uv.fs_stat(path) then return {} end
  local fd = io.open(path, "r")
  if not fd then return {} end
  local content = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then return {} end
  local names = {}
  for k, _ in pairs(decoded) do
    if type(k) == "string" then table.insert(names, k) end
  end
  table.sort(names)
  return names
end

local function apply_env(name, silent)
  local ok, kulala = pcall(require, "kulala")
  if ok and type(kulala.set_selected_env) == "function" then
    kulala.set_selected_env(name)
  else
    -- Fallback for older kulala versions: selected env is read from
    -- vim.g.kulala_selected_env at request time.
    vim.g.kulala_selected_env = name
  end
  if not silent then
    vim.notify("rest: env set to " .. name, vim.log.levels.INFO)
  end
end

-- --------------------------------------------------------------------------
-- Scaffold + scratch
-- --------------------------------------------------------------------------

function M.scaffold()
  local root = M.root()
  for _, d in ipairs({
    root,
    root .. "/http",
    root .. "/http/generated",
    root .. "/http/local",
  }) do
    mkdir_p(d)
  end

  local files = {
    { root .. "/.gitignore", GITIGNORE },
    { root .. "/README.md", README },
    { root .. "/" .. ENV_FILE, PRIVATE_ENV },
    { root .. "/http/local/scratch.http", SCRATCH_HTTP },
    { root .. "/http/generated/.gitkeep", "" },
  }

  local created = {}
  for _, spec in ipairs(files) do
    if write_if_missing(spec[1], spec[2]) then
      table.insert(created, vim.fn.fnamemodify(spec[1], ":."))
    end
  end

  -- Link the default env so the user doesn't have to pick after scaffold.
  local cache = read_cache()
  if not cache[CACHE_KEY] or cache[CACHE_KEY] == "" then
    cache[CACHE_KEY] = DEFAULT_ENV_NAME
    write_cache(cache)
  end
  apply_env(cache[CACHE_KEY], true)

  if #created == 0 then
    vim.notify("rest: .rest/ already scaffolded at " .. root, vim.log.levels.INFO)
  else
    table.sort(created)
    vim.notify("rest: scaffolded " .. #created .. " files:\n  " .. table.concat(created, "\n  "), vim.log.levels.INFO)
  end
  return root
end

function M.new_scratch()
  local root = M.root()
  if not vim.uv.fs_stat(root) then
    M.scaffold()
  end
  local stamp = os.date("%Y%m%d-%H%M%S")
  local path = string.format("%s/http/local/scratch-%s.http", root, stamp)
  write_if_missing(path, SCRATCH_HTTP)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

-- --------------------------------------------------------------------------
-- Env selection / display / autoload
-- --------------------------------------------------------------------------

function M.env_select()
  if not vim.uv.fs_stat(env_file_path()) then
    vim.notify("rest: no " .. ENV_FILE .. "; run :RestScaffold first", vim.log.levels.WARN)
    return
  end

  local names = list_env_names()
  if #names == 0 then
    vim.notify("rest: " .. ENV_FILE .. " has no envs", vim.log.levels.WARN)
    return
  end

  vim.ui.select(names, {
    prompt = "Rest env (cached after pick)",
  }, function(choice)
    if not choice then return end
    apply_env(choice)
    local cache = read_cache()
    cache[CACHE_KEY] = choice
    write_cache(cache)
  end)
end

function M.env_show()
  local cache = read_cache()
  local name = cache[CACHE_KEY]
  if not name or name == "" then
    name = vim.g.kulala_selected_env
  end
  vim.notify("rest: current env = " .. (name or "<none>"), vim.log.levels.INFO)
end

-- If the cache exists and names a real env, apply it silently.
function M.env_autoload()
  local cache = read_cache()
  local name = cache[CACHE_KEY]
  if not name or name == "" then return end
  apply_env(name, true)
end

-- BufEnter hook: when a `.http` file under this project's `.rest/` tree opens,
-- apply the cached env silently. Safe no-op when there's no cache.
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.http",
  callback = function(ev)
    local buf_path = vim.api.nvim_buf_get_name(ev.buf)
    if buf_path == "" then return end
    local rest_root = M.root()
    if not buf_path:find(rest_root, 1, true) then return end
    vim.schedule(function() M.env_autoload() end)
  end,
})

return M
