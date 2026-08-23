-- The agent roster, for the navigation modal.
--
-- Two sources, in order:
--
--  1. auto-agents' live config — `state.config.agents.bootstrap`. Canonical,
--     and the same field `auto-agents/dock/init.lua` reads. Getting this path
--     wrong is what made the modal's agents group always empty: v0.4.0 read
--     `state.config.agents` and iterated it as a list, but the list lives one
--     level down under `.bootstrap` (see `config/store.lua`), so the probe
--     found nothing, fell back to a single "open agents panel" row, and no
--     agent was ever individually reachable.
--
--  2. the project's `.auto-agents-config/*.toml`, parsed directly, when
--     auto-agents has not loaded yet. Deliberate: auto-agents is lazy-loaded
--     (`keys`/`cmd`), so `state.config` is nil until the panel is first opened
--     some other way — and a navigation modal that cannot reach agents until
--     you have already reached them defeats the point of replacing F5.
--     Requiring an auto-agents module to get the roster would force the whole
--     plugin to load just to draw a menu, so we read the file instead.
--
-- Slot 0 is always the admin REPL, never an entry in the roster file.

local M = {}

M.DEFAULT_MAX_SLOT = 5

M.probe = {
  config_dir = function()
    return vim.fn.stdpath("config") .. "/.auto-agents-config"
  end,
  cwd = function()
    return vim.fn.getcwd()
  end,
  read = function(path)
    if vim.fn.filereadable(path) ~= 1 then
      return nil
    end
    return table.concat(vim.fn.readfile(path), "\n")
  end,
  glob = function(pat)
    return vim.fn.glob(pat, false, true)
  end,
}

---Pull `[[agents]]` rows out of a TOML body.
---
---Intentionally NOT a TOML parser. It reads exactly the four scalar keys the
---modal needs from a shape auto-agents itself writes, and ignores everything
---else. A real parser here would be a second implementation of auto-agents'
---config format with its own bugs; this cannot silently disagree about
---anything beyond these keys.
---@param body string
---@return table[]  list of { slot, name, title, kind }
function M.parse_agents(body)
  local out = {}
  if type(body) ~= "string" then
    return out
  end
  -- Split on the array-of-tables header, then read scalars out of each chunk
  -- up to the next `[` section start so keys from a later table cannot leak in.
  for chunk in body:gmatch("%[%[agents%]%]([^%[]*)") do
    local slot = tonumber(chunk:match("%f[%w]slot%s*=%s*(%d+)"))
    if slot then
      out[#out + 1] = {
        slot = slot,
        name = chunk:match('%f[%w]name%s*=%s*"([^"]*)"'),
        title = chunk:match('%f[%w]title%s*=%s*"([^"]*)"'),
        kind = chunk:match('%f[%w]kind%s*=%s*"([^"]*)"'),
      }
    end
  end
  return out
end

---Which TOML auto-agents would use here: a per-project file whose
---`[project] cwd` matches, else `global.toml`. Mirrors `config/store.lua`.
---@return string|nil path
function M.active_toml()
  local dir = M.probe.config_dir()
  local cwd = vim.fs and vim.fs.normalize(M.probe.cwd()) or M.probe.cwd()
  local global
  for _, path in ipairs(M.probe.glob(dir .. "/*.toml")) do
    if vim.fn.fnamemodify(path, ":t") == "global.toml" then
      global = path
    else
      local body = M.probe.read(path)
      local pcwd = body and body:match('%f[%w]cwd%s*=%s*"([^"]*)"')
      if pcwd and pcwd ~= "" then
        pcwd = vim.fs and vim.fs.normalize(pcwd) or pcwd
        -- Exact match or an ancestor of cwd — a worktree under the project
        -- root is still that project.
        if cwd == pcwd or cwd:sub(1, #pcwd + 1) == pcwd .. "/" then
          return path
        end
      end
    end
  end
  return global
end

---The roster as the modal should render it: slot 0 (admin) through the highest
---configured slot, each with a display label.
---@return table[] list of { slot, label }
function M.slots()
  local rows, max_slot = nil, nil

  local ok, aa = pcall(require, "auto-agents")
  if ok and type(aa) == "table" then
    local cfg = (aa.state or {}).config
    -- `.bootstrap` — the path the dock uses. See the note at the top.
    local bs = cfg and (cfg.agents or {}).bootstrap or nil
    if type(bs) == "table" and #bs > 0 then
      rows = bs
      max_slot = tonumber(aa.MAX_SLOT)
    end
  end

  if not rows then
    local path = M.active_toml()
    local body = path and M.probe.read(path) or nil
    rows = body and M.parse_agents(body) or {}
  end

  local by_slot = {}
  local highest = 0
  for _, e in ipairs(rows) do
    local s = tonumber(e.slot)
    if s then
      -- `name` first, deliberately diverging from the dock's `title` first.
      -- The dock is a status surface where "Ultron (working)" reads well; this
      -- is a navigation surface, and the name is the agent's actual identity —
      -- the string that appears in `$AUTO_AGENTS_MAILBOX_ID`, in assignments
      -- and in every log line. `ultron-prime` is addressable; `Ultron` is a
      -- nickname for it.
      by_slot[s] = e.name or e.title or e.kind or "agent"
      if s > highest then
        highest = s
      end
    end
  end

  -- Show every slot the panel has, not just the configured ones: an empty slot
  -- is still navigable and its emptiness is worth seeing.
  max_slot = max_slot or math.max(highest, M.DEFAULT_MAX_SLOT)

  local out = { { slot = 0, label = "admin" } }
  for s = 1, max_slot do
    out[#out + 1] = { slot = s, label = by_slot[s] or "(empty)" }
  end
  return out
end

return M
