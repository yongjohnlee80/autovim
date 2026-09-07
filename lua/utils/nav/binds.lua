-- User-assigned single-letter shortcuts for the navigation modal.
--
-- Requirement 7: highlight a destination, press `*`, give it a letter. From
-- then on the modal lists that letter at the TOP level, so a frequent
-- destination costs two keystrokes total (`<C-g>` then the letter) instead of
-- drilling through a group.
--
-- Stored in `stdpath("state")/autovim-nav-binds.json`, SCOPED PER WORKSPACE:
--
--     { "/home/you/Source/proj": { "d": "finder.repos" },
--       "/home/you/.config/nvim": { "d": "agents.jarvis" } }
--
-- The scoping is not cosmetic. A destination id only means something inside
-- the workspace that produced it: auto-finder's enabled sections and the
-- auto-agents roster are both per-project config, so `finder.todos` exists in
-- one project and not the next, and `agents.lector` names an agent that a
-- different project has never heard of. A single global map therefore made
-- every letter either dead (silently hidden, because its destination is gone)
-- or wrong for all but the workspace it was created in. One bucket per
-- workspace lets the same letter mean the right thing in each.
--
-- Destination ids are stable strings like `finder.dbase`, so a bind survives
-- sections being reordered — which an index-based bind would not.
--
-- A bind pointing at a destination that no longer exists (a renamed agent, a
-- disabled section) is kept on disk but not shown; removing it silently would
-- lose the user's choice the first time they open Neovim without that plugin.

local M = {}

-- Movement and dismissal keys the modal owns. Binding these would make the
-- modal unusable, so they are refused with an explanation.
--
-- `h` is in this list because the modal MAPS it (back up a level) and the
-- a-z bind loop in `ui.lua` skips exactly this set. When `h` was missing, that
-- loop re-mapped it to "resolve the letter through the user's binds" — which
-- silently overwrote the back mapping, so the modal advertised `h back` in its
-- hint line while only `<BS>` actually worked.
M.RESERVED = { h = true, j = true, k = true, q = true }

-- Test seams.
M._path_override = nil
M._workspace_override = nil

local function path()
  return M._path_override or (vim.fn.stdpath("state") .. "/autovim-nav-binds.json")
end

function M.path()
  return path()
end

---The workspace these binds belong to.
---
---Resolved through `utils.scope`, i.e. auto-core's canonical `$WORKSPACE` with
---a cwd fallback — the same resolver lazygit and the Root-Dir pickers use, so
---"which project am I in" cannot mean two different things across AutoVim.
---Resolved per CALL, never cached, so switching worktrees mid-session switches
---the bind set with it.
---@return string
function M.workspace()
  if M._workspace_override then
    return M._workspace_override
  end
  local ok, scope = pcall(require, "utils.scope")
  local root = ok and scope.workspace_root() or vim.fn.getcwd()
  return vim.fs and vim.fs.normalize(root) or root
end

---Keep only well-formed single-letter -> destination-id pairs. A hand-edited or
---truncated file must not take the modal down.
---@param tbl any
---@return table<string,string>
local function sanitize(tbl)
  local out = {}
  if type(tbl) ~= "table" then
    return out
  end
  for key, id in pairs(tbl) do
    -- `%a`, not `%l`: capitals are valid binds so opposing actions can pair
    -- (`d`/`D`, `o`/`O`). Case SEPARATES — they are two independent slots, and
    -- folding them here would silently merge a pair on the next read.
    if type(key) == "string" and key:match("^%a$") and type(id) == "string" and id ~= "" then
      out[key] = id
    end
  end
  return out
end

---@return table  raw decoded file contents, or `{}`
local function read_file()
  local p = path()
  if vim.fn.filereadable(p) ~= 1 then
    return {}
  end
  local raw = table.concat(vim.fn.readfile(p), "\n")
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

---Write the whole store. Sorted at both levels so the file has a stable diff
---rather than Lua's hash order; empty buckets are dropped rather than
---accumulating as `{}` for every workspace ever opened.
---@param store table<string, table<string,string>>
---@return boolean ok, string|nil err
local function write_file(store)
  local p = path()
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
    local roots = {}
    for root, binds in pairs(store) do
      if type(binds) == "table" and next(binds) ~= nil then
        roots[#roots + 1] = root
      end
    end
    table.sort(roots)
    local blocks = {}
    for _, root in ipairs(roots) do
      local letters = vim.tbl_keys(store[root])
      table.sort(letters)
      local parts = {}
      for _, k in ipairs(letters) do
        parts[#parts + 1] = ("    %s: %s"):format(vim.json.encode(k), vim.json.encode(store[root][k]))
      end
      blocks[#blocks + 1] = ("  %s: {\n%s\n  }"):format(vim.json.encode(root), table.concat(parts, ",\n"))
    end
    vim.fn.writefile(vim.split("{\n" .. table.concat(blocks, ",\n") .. "\n}", "\n"), p)
  end)
  if not ok then
    return false, tostring(err)
  end
  return true
end

---The whole store, split into per-workspace buckets and any leftover pairs
---from the pre-scoping flat format (`{"d": "finder.repos"}` at the top level).
---@return table<string, table<string,string>> store, table<string,string> legacy
function M.load_all()
  local store, legacy = {}, {}
  for key, value in pairs(read_file()) do
    if type(value) == "table" then
      store[key] = sanitize(value)
    elseif type(value) == "string" then
      legacy[key] = value
    end
  end
  return store, sanitize(legacy)
end

---The binds for the CURRENT workspace.
---
---A pre-scoping flat file is migrated on first read: its pairs were global, so
---they fold into whichever workspace is open when the migration runs, and the
---file is rewritten in the nested format immediately. Migrating in place —
---rather than leaving the flat pairs as a permanent fallback — keeps exactly
---one shape on disk and one answer to "why is this letter here".
---@return table<string,string>
function M.load()
  local store, legacy = M.load_all()
  local ws = M.workspace()
  local mine = store[ws] or {}
  if next(legacy) ~= nil then
    for letter, id in pairs(legacy) do
      if mine[letter] == nil then
        mine[letter] = id
      end
    end
    store[ws] = mine
    write_file(store)
  end
  return mine
end

---Replace the CURRENT workspace's binds, leaving every other workspace alone.
---@param tbl table<string,string>
---@return boolean ok, string|nil err
function M.save(tbl)
  local store = M.load_all()
  store[M.workspace()] = sanitize(tbl)
  return write_file(store)
end

---Validate a candidate key. Returns nil when acceptable, else the reason.
---@param key string
---@return string|nil
function M.reject_reason(key)
  -- Lowercase-only was the original rule and no rationale for it was ever
  -- recorded. Nothing technical required it: the modal dispatches through
  -- `vim.keymap.set`, which is case-sensitive and handles uppercase natively.
  -- Capitals let opposing destinations pair under one letter (Johno, 2026-09-07).
  if type(key) ~= "string" or not key:match("^%a$") then
    return "pick a single letter (a-z or A-Z)"
  end
  if M.RESERVED[key] then
    return ("`%s` is reserved by the modal (j/k move, h backs up, q closes)"):format(key)
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
    return false, ("nothing bound to `%s` in this workspace"):format(tostring(key))
  end
  binds[key] = nil
  return M.save(binds)
end

---The letter currently pointing at `id` in this workspace, or nil.
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
