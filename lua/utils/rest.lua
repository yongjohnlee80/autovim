-- Scaffolding and helpers for rest.nvim collections.
--
-- Project layout created under <project>/.rest/:
--
--   .rest/
--     http/
--       generated/   -- auto-generated from openapi-v3.yaml or route-*.go
--       local/       -- human-authored .http files
--     env/
--       shared.env   -- committed defaults
--       dev.env      -- committed dev overrides
--       local.env    -- gitignored secrets
--     .gitignore
--     README.md

local M = {}

local GITIGNORE = [[
# Local-only env files; never commit
local.env
*.local.env

# Saved response dumps
**/*.response
**/*.response.json
]]

local SHARED_ENV = [[
# Shared, non-secret defaults. Committed.
# Requests reference these via {{VAR}} substitution.
BASE_URL=http://localhost:8080
API_VERSION=v1
]]

local DEV_ENV = [[
# Dev overrides. Committed.
BASE_URL=http://localhost:8080
]]

local LOCAL_ENV = [[
# Local secrets. GITIGNORED.
# Put tokens, passwords, and any other sensitive values here.
# API_TOKEN=
# BASIC_AUTH_USER=
# BASIC_AUTH_PASS=
]]

local SCRATCH_HTTP = [[
### Scratch request
# @env ../../env/dev.env

GET {{BASE_URL}}/healthz
Accept: application/json

###
]]

local README = [[
# .rest

Per-project REST client collection consumed by `rest.nvim`.

## Layout

- `http/generated/` - auto-generated from `openapi-v3.yaml` or `route-*.go`.
  Treat as disposable; regenerate instead of hand-editing.
- `http/local/` - human-authored `.http` files for ad-hoc and exploratory requests.
- `env/shared.env` - shared defaults. Committed.
- `env/dev.env` - dev overrides. Committed.
- `env/local.env` - secrets. **Gitignored.**

## Selecting an environment

Pin an env per-file with a magic comment near the top:

    # @env ../../env/dev.env

Or switch at runtime:

    :Rest env set .rest/env/dev.env
    :Rest env show

## Secrets

`env/local.env` is gitignored by the scaffolded `.gitignore`. Put tokens,
passwords, and session cookies there. `shared.env` and `dev.env` must stay
non-sensitive so they can be committed safely.

## Running a request

Place the cursor inside a request block and run `:Rest run`
(`<leader>Rr`). `:Rest last` (`<leader>Rl`) re-runs the previous request.

## First-time setup (Arch)

`rest.nvim` v3 builds luarocks dependencies on first install, and the
`tree-sitter-http` rock needs Lua 5.1 headers. On Arch, install the AUR
`lua51` package (`yay -S lua51`) and run `:Lazy build rest.nvim`.
]]

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

local function project_root()
  local ok, lv = pcall(require, "lazyvim.util")
  if ok and type(lv.root) == "function" then
    local r = lv.root()
    if type(r) == "string" and r ~= "" then
      return r
    end
  end
  local git = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and git[1] and git[1] ~= "" then
    return git[1]
  end
  return vim.fn.getcwd()
end

function M.root()
  return project_root() .. "/.rest"
end

function M.scaffold()
  local root = M.root()
  for _, d in ipairs({
    root,
    root .. "/http",
    root .. "/http/generated",
    root .. "/http/local",
    root .. "/env",
  }) do
    mkdir_p(d)
  end

  local files = {
    { root .. "/.gitignore", GITIGNORE },
    { root .. "/README.md", README },
    { root .. "/env/shared.env", SHARED_ENV },
    { root .. "/env/dev.env", DEV_ENV },
    { root .. "/env/local.env", LOCAL_ENV },
    { root .. "/http/local/scratch.http", SCRATCH_HTTP },
    { root .. "/http/generated/.gitkeep", "" },
  }

  local created = {}
  for _, spec in ipairs(files) do
    if write_if_missing(spec[1], spec[2]) then
      table.insert(created, vim.fn.fnamemodify(spec[1], ":."))
    end
  end

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

-- Open a :Rest env select-style picker but rooted at the project's .rest/env
-- directory, regardless of where the current buffer lives.
function M.env_select()
  local env_dir = M.root() .. "/env"
  if vim.fn.isdirectory(env_dir) == 0 then
    vim.notify("rest: no .rest/env directory; run :RestScaffold first", vim.log.levels.WARN)
    return
  end
  local files = vim.fn.glob(env_dir .. "/*.env", false, true)
  if #files == 0 then
    vim.notify("rest: no env files in " .. env_dir, vim.log.levels.WARN)
    return
  end
  vim.ui.select(files, { prompt = "Rest env" }, function(choice)
    if not choice then return end
    vim.cmd("Rest env set " .. vim.fn.fnameescape(choice))
    vim.notify("rest: env set to " .. vim.fn.fnamemodify(choice, ":."), vim.log.levels.INFO)
  end)
end

return M
