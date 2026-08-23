-- User-assigned single-letter shortcuts for the navigation modal.
--
-- Requirement 7: highlight a destination, press `*`, give it a letter. From
-- then on the modal lists that letter at the TOP level, so a frequent
-- destination costs two keystrokes total (`<C-g>` then the letter) instead of
-- drilling through a group.
--
-- Stored as `{ "<letter>": "<destination id>" }` in
-- `stdpath("state")/autovim-nav-binds.json`. Destination ids are stable strings
-- like `finder.dbase`, so a bind survives sections being reordered — which an
-- index-based bind would not.
--
-- A bind pointing at a destination that no longer exists (a renamed agent, a
-- disabled section) is kept on disk but not shown; removing it silently would
-- lose the user's choice the first time they open Neovim without that plugin.

local M = {}

-- Movement and dismissal keys the modal owns. Binding these would make the
-- modal unusable, so they are refused with an explanation.
M.RESERVED = { j = true, k = true, q = true }

-- Test seam.
M._path_override = nil

local function path()
  return M._path_override or (vim.fn.stdpath("state") .. "/autovim-nav-binds.json")
end

function M.path()
  return path()
end

---@return table<string,string>
function M.load()
  local p = path()
  if vim.fn.filereadable(p) ~= 1 then
    return {}
  end
  local raw = table.concat(vim.fn.readfile(p), "\n")
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  -- Drop anything that is not a single-letter -> string pair. A hand-edited or
  -- truncated file must not take the modal down.
  local out = {}
  for key, id in pairs(decoded) do
    if type(key) == "string" and key:match("^%l$") and type(id) == "string" and id ~= "" then
      out[key] = id
    end
  end
  return out
end

---@param tbl table<string,string>
---@return boolean ok, string|nil err
function M.save(tbl)
  local p = path()
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
    -- Sorted keys so the file has a stable diff rather than Lua's hash order.
    local keys = vim.tbl_keys(tbl)
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = ("  %s: %s"):format(vim.json.encode(k), vim.json.encode(tbl[k]))
    end
    vim.fn.writefile(vim.split("{\n" .. table.concat(parts, ",\n") .. "\n}", "\n"), p)
  end)
  if not ok then
    return false, tostring(err)
  end
  return true
end

---Validate a candidate key. Returns nil when acceptable, else the reason.
---@param key string
---@return string|nil
function M.reject_reason(key)
  if type(key) ~= "string" or not key:match("^%l$") then
    return "pick a single lowercase letter (a-z)"
  end
  if M.RESERVED[key] then
    return ("`%s` is reserved by the modal (j/k move, q closes)"):format(key)
  end
  return nil
end

---Assign `key` to `id`, replacing any previous holder of that key and any
---previous key for that id (a destination gets ONE shortcut, and a key points
---at ONE destination — otherwise the top-level list grows duplicates).
---@return boolean ok, string|nil err
function M.bind(key, id)
  local reason = M.reject_reason(key)
  if reason then
    return false, reason
  end
  if type(id) ~= "string" or id == "" then
    return false, "no destination to bind"
  end
  local binds = M.load()
  for k, v in pairs(binds) do
    if v == id then
      binds[k] = nil
    end
  end
  binds[key] = id
  return M.save(binds)
end

---@return boolean ok, string|nil err
function M.unbind(key)
  local binds = M.load()
  if binds[key] == nil then
    return false, ("nothing bound to `%s`"):format(tostring(key))
  end
  binds[key] = nil
  return M.save(binds)
end

---The letter currently pointing at `id`, or nil.
---@return string|nil
function M.key_for(id)
  for k, v in pairs(M.load()) do
    if v == id then
      return k
    end
  end
  return nil
end

return M
