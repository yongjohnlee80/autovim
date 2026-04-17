-- go-test-env: merge a VSCode-style launch.json into nvim-dap-go's debug_test().
--
-- Why this exists
--   VSCode's Go extension resolves `buildFlags`, `env`, and `envFile` from
--   launch.json before sending the request to delve. Under Neovim +
--   nvim-dap + delve's DAP server, `env` is forwarded but `envFile` is
--   silently dropped — it's a VSCode client-side feature. This module
--   parses the file itself, folds it into `env`, and hands the result to
--   nvim-dap-go's `debug_test(custom_config)`.
--
-- Scope: only `type="go", mode="test"` configurations are considered.
-- Non-goals: arbitrary launch.json emulation (preLaunchTask, compound
-- configs, variable substitution beyond `${workspaceFolder}`/`~`/`$VAR`).
--
-- Requires Neovim 0.9+ (vim.json, vim.log.levels, vim.tbl_count).

---@class GoTestEnv.Opts
---@field launch_paths? string[]     Relative paths searched (in order) for launch.json. Default: {".vscode/launch.json", "launch.json"}.
---@field config_name? string        Select a launch config by `name`. Nil → first matching type=go, mode=test entry.
---@field notify_level? integer      Minimum level for notifications (vim.log.levels). Default: INFO.
---@field expand_env_values? boolean Run vim.fn.expand() on inline `env` values too. Default: false (avoids mangling values with $ chars).

---@class GoTestEnv.Result
---@field buildFlags? string
---@field env? table<string,string>

local M = {}

---@type GoTestEnv.Opts
local defaults = {
  launch_paths = { ".vscode/launch.json", "launch.json" },
  config_name = nil,
  notify_level = vim.log.levels.INFO,
  expand_env_values = false,
}

---@type GoTestEnv.Opts
local opts = vim.deepcopy(defaults)

-- { path = string|nil, mtime = integer|nil, config = GoTestEnv.Result } | nil
local cache = nil

local uv = vim.uv or vim.loop

local function notify(msg, level)
  level = level or vim.log.levels.INFO
  if level < (opts.notify_level or vim.log.levels.INFO) then return end
  vim.schedule(function() vim.notify("[go-test-env] " .. msg, level) end)
end

---@return string
local function global_cwd()
  return uv.cwd() or vim.fn.getcwd(-1, -1)
end

-- Value-level substitution: only `${workspaceFolder}`. Safe for env values
-- that may contain literal `$` (bcrypt hashes, passwords, cron expressions).
---@param v any
---@return any
local function sub_workspace(v)
  if type(v) ~= "string" then return v end
  return (v:gsub("%${workspaceFolder}", global_cwd()))
end

-- Path-level substitution: ${workspaceFolder} + shell ~ / $VAR / <token>.
---@param v any
---@return any
local function sub_path(v)
  if type(v) ~= "string" then return v end
  return vim.fn.expand(sub_workspace(v))
end

-- Parse a .env-style file. Supports:
--   KEY=VAL              unquoted; trailing chars preserved verbatim
--   KEY="VAL" / 'VAL'    surrounding quotes stripped, contents literal
--   export KEY=VAL       leading `export ` stripped
--   # line comments, blank lines skipped
-- Does not: interpret escape sequences, strip mid-line comments, join
-- multi-line values.
---@param path string
---@return table<string,string>|nil, string|nil
local function parse_envfile(path)
  local f = io.open(path, "r")
  if not f then return nil, "cannot open " .. path end
  local out = {}
  for line in f:lines() do
    local s = line:gsub("^%s+", ""):gsub("%s+$", "")
    if s ~= "" and s:sub(1, 1) ~= "#" then
      s = s:gsub("^export%s+", "")
      local key, val = s:match("^([%a_][%w_%-%.]*)%s*=%s*(.*)$")
      if key then
        local q = val:sub(1, 1)
        if (q == '"' or q == "'") and #val >= 2 and val:sub(-1) == q then
          val = val:sub(2, -2)
        end
        out[key] = val
      end
    end
  end
  f:close()
  return out, nil
end

-- Strip // and /* */ comments from a JSON-with-comments string, respecting
-- string boundaries so `postgres://...` inside a value stays intact.
---@param s string
---@return string
local function strip_json_comments(s)
  local out, i, n = {}, 1, #s
  local in_string, escape = false, false
  while i <= n do
    local c = s:sub(i, i)
    if in_string then
      out[#out + 1] = c
      if escape then
        escape = false
      elseif c == "\\" then
        escape = true
      elseif c == '"' then
        in_string = false
      end
      i = i + 1
    elseif c == '"' then
      in_string = true
      out[#out + 1] = c
      i = i + 1
    elseif c == "/" and s:sub(i + 1, i + 1) == "/" then
      local nl = s:find("\n", i + 2, true)
      i = nl or (n + 1)
    elseif c == "/" and s:sub(i + 1, i + 1) == "*" then
      local close = s:find("*/", i + 2, true)
      i = close and (close + 2) or (n + 1)
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

---@param content string
---@return table|nil, string|nil
local function parse_launchjs(content)
  content = strip_json_comments(content)
  content = content:gsub(",(%s*[%]}])", "%1")
  local ok, data = pcall(vim.json.decode, content)
  if not ok then return nil, tostring(data) end
  return data, nil
end

---@param override string?
---@return string?
local function resolve_path(override)
  if override and override ~= "" then
    return vim.fn.fnamemodify(override, ":p")
  end
  local cwd = global_cwd()
  for _, rel in ipairs(opts.launch_paths or defaults.launch_paths) do
    local p = cwd .. "/" .. rel
    if vim.fn.filereadable(p) == 1 then return p end
  end
  return nil
end

---@param parsed table
---@return table|nil
local function pick_config(parsed)
  if type(parsed) ~= "table" or type(parsed.configurations) ~= "table" then
    return nil
  end
  local name = opts.config_name
  for _, c in ipairs(parsed.configurations) do
    if c.type == "go" and c.mode == "test" and (not name or c.name == name) then
      return c
    end
  end
  return nil
end

---@param raw table
---@return GoTestEnv.Result
local function normalize(raw)
  ---@type GoTestEnv.Result
  local out = {}
  if type(raw.buildFlags) == "string" and raw.buildFlags ~= "" then
    out.buildFlags = sub_workspace(raw.buildFlags)
  end
  local merged = {}
  if type(raw.envFile) == "string" and raw.envFile ~= "" then
    local path = sub_path(raw.envFile)
    local parsed, err = parse_envfile(path)
    if parsed then
      for k, v in pairs(parsed) do merged[k] = v end
    else
      notify("envFile " .. tostring(err), vim.log.levels.WARN)
    end
  end
  if type(raw.env) == "table" then
    local xform = opts.expand_env_values and sub_path or sub_workspace
    for k, v in pairs(raw.env) do merged[k] = xform(v) end
  end
  if next(merged) then out.env = merged end
  return out
end

---@param path string
---@return integer?
local function mtime_of(path)
  local s = uv.fs_stat(path)
  return s and s.mtime and s.mtime.sec or nil
end

--- Load (and cache) a normalized config from launch.json. The cache invalidates
--- automatically when launch.json's mtime changes; it does NOT watch the
--- referenced envFile — use `:GoTestEnvReload` (or `M.reload()`) after editing it.
---@param override_path string?
---@return GoTestEnv.Result
function M.load(override_path)
  local path = resolve_path(override_path)
  if not path then
    notify(
      "no launch.json found (searched " .. table.concat(opts.launch_paths or defaults.launch_paths, ", ") .. ")",
      vim.log.levels.WARN
    )
    cache = { path = nil, mtime = nil, config = {} }
    return cache.config
  end

  local mtime = mtime_of(path)
  if cache and cache.path == path and cache.mtime == mtime and not override_path then
    return cache.config
  end

  local f = io.open(path, "r")
  if not f then
    notify("could not read " .. path, vim.log.levels.ERROR)
    cache = { path = path, mtime = mtime, config = {} }
    return cache.config
  end
  local content = f:read("*a")
  f:close()

  local parsed, err = parse_launchjs(content)
  if not parsed then
    notify("parse failed: " .. tostring(err), vim.log.levels.ERROR)
    cache = { path = path, mtime = mtime, config = {} }
    return cache.config
  end

  local raw = pick_config(parsed)
  if not raw then
    local suffix = opts.config_name and (" matching name=" .. opts.config_name) or ""
    notify("no Go test config" .. suffix .. " in " .. path, vim.log.levels.WARN)
    cache = { path = path, mtime = mtime, config = {} }
    return cache.config
  end

  local config = normalize(raw)
  cache = { path = path, mtime = mtime, config = config }

  local parts = {}
  if config.buildFlags then parts[#parts + 1] = "buildFlags=" .. config.buildFlags end
  if config.env then parts[#parts + 1] = "env=" .. tostring(vim.tbl_count(config.env)) .. " keys" end
  notify(
    ("loaded %s%s"):format(path, #parts > 0 and " (" .. table.concat(parts, ", ") .. ")" or ""),
    vim.log.levels.INFO
  )
  return config
end

--- Clear the cache and immediately reload.
---@param override_path string?
---@return GoTestEnv.Result
function M.reload(override_path)
  cache = nil
  return M.load(override_path)
end

--- Report what's currently cached.
function M.status()
  if not cache then
    notify("not yet loaded", vim.log.levels.INFO)
    return
  end
  notify(
    ("cached from %s: %s"):format(cache.path or "<none>", vim.inspect(cache.config)),
    vim.log.levels.INFO
  )
end

--- Run the test under the cursor with the cached launch.json config merged in.
---@param override_path string?
function M.debug_test(override_path)
  local ok, dap_go = pcall(require, "dap-go")
  if not ok then
    notify("require('dap-go') failed — install nvim-dap-go", vim.log.levels.ERROR)
    return
  end
  dap_go.debug_test(M.load(override_path))
end

--- Configure module behavior. Merges over defaults; invalidates the cache.
---@param user_opts GoTestEnv.Opts?
function M.setup(user_opts)
  opts = vim.tbl_deep_extend("force", defaults, user_opts or {})
  cache = nil
end

pcall(vim.api.nvim_create_user_command, "GoTestEnvReload", function(cmd)
  M.reload(cmd.args ~= "" and cmd.args or nil)
end, { nargs = "?", complete = "file", desc = "Reload go-test-env launch.json cache" })

pcall(vim.api.nvim_create_user_command, "GoTestEnvStatus", function()
  M.status()
end, { desc = "Show the cached go-test-env config" })

return M
