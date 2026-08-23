-- The navigation modal's destination tree.
--
-- Requirement 7 replaces the F-key sprawl (F1..F4 terminals, F5 agents, F6/F12
-- dock, F11 diff queue) with one modal on `<C-g>`. F-keys are unreliable across
-- terminals, multiplexers and SSH; a single leader-ish key plus one or two
-- keystrokes is both more portable and faster.
--
-- Everything here is DISCOVERED, not hard-coded. AutoVim enables 3 of
-- auto-finder's 9 views and the agent roster is per-project TOML, so a static
-- list would be wrong on every machine but this one. Each group's builder
-- probes its plugin and returns an empty list when the plugin is absent, so the
-- modal degrades to whatever is actually installed.
--
-- Actions are DECLARATIVE (`{ kind = "cmd", value = "AutoFinderFocus 2" }`)
-- rather than opaque closures, so `tests/smoke.lua` can assert that
-- `finder.dbase` dispatches the right command without a running panel.

local M = {}

---@alias NavAction { kind: "cmd"|"system"|"fn", value: string|function|nil, argv: string[]|nil }
---@alias NavDest { id: string, label: string, action: NavAction, detail: string|nil }
---@alias NavGroup { id: string, label: string, children: NavDest[] }

-- Probes live in a table so tests can substitute them. Each returns a plain
-- list and MUST NOT raise: a broken or half-loaded plugin should cost you that
-- one group, not the whole modal.
local DEFAULT_PROBES = {
  -- Every panel slot with a display label: slot 0 is the admin REPL, then one
  -- row per agent. Resolution (live config, else the project TOML) and the
  -- reason it is not read from `state.config.agents` live in `nav.roster`.
  agents = function()
    local ok, roster = pcall(require, "utils.nav.roster")
    if not ok then
      return {}
    end
    local okc, slots = pcall(roster.slots)
    return okc and slots or {}
  end,

  -- Section NAMES in panel order; the index is what `AutoFinderFocus` takes.
  finder_sections = function()
    local ok, af = pcall(require, "auto-finder")
    if not ok or type(af) ~= "table" then
      return {}
    end
    local cfg = (af.state or {}).config
    local sections = cfg and cfg.sections or nil
    if type(sections) ~= "table" then
      return {}
    end
    local out = {}
    for _, name in ipairs(sections) do
      if type(name) == "string" then
        out[#out + 1] = name
      end
    end
    return out
  end,

  -- Open editor buffers, most-recently-used first.
  --
  -- Filtered to real files: a listed, loaded, named buffer with an ordinary
  -- buftype. That drops the panel, the agent slots, the playground terminals,
  -- help, quickfix and the modal's own scratch buffer — none of which a
  -- "jump to a buffer" list should offer, and several of which are reachable
  -- through their own group already.
  buffers = function()
    local out = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(b)
      if vim.bo[b].buflisted
        and vim.api.nvim_buf_is_loaded(b)
        and vim.bo[b].buftype == ""
        and name ~= ""
      then
        out[#out + 1] = {
          bufnr = b,
          name = vim.fn.fnamemodify(name, ":~:."),
          lastused = vim.fn.getbufinfo(b)[1] and vim.fn.getbufinfo(b)[1].lastused or 0,
        }
      end
    end
    table.sort(out, function(x, y)
      return x.lastused > y.lastused
    end)
    return out
  end,

  -- T1..T4 exist whenever auto-agents does; they are created on first toggle.
  terminals = function()
    local ok = pcall(require, "auto-agents.term")
    if not ok then
      return {}
    end
    return { 1, 2, 3, 4 }
  end,

  -- Requirement: ONE browser option — open in a tmux split pane.
  --
  -- terminal-browser paints via the kitty graphics protocol, which Neovim's
  -- libvterm neither implements nor forwards (see KB ADR-0062), so it cannot
  -- render in a Neovim terminal at all. A sibling tmux pane is a real terminal
  -- talking straight to the host, which is why THAT works. Hence both
  -- conditions: the binary, and actually being inside tmux.
  browser = function()
    if vim.fn.executable("terminal-browser") ~= 1 then
      return false
    end
    return type(vim.env.TMUX) == "string" and vim.env.TMUX ~= ""
  end,

  -- A command is only offered if it actually exists in this session.
  has_command = function(name)
    return vim.fn.exists(":" .. name) == 2
  end,
}

function M.reset_probes()
  M.probe = vim.tbl_extend("force", {}, DEFAULT_PROBES)
end

M.reset_probes()

M.BROWSER_SPLIT = { "right", "0.5" }

---Build the destination tree: an ordered list of groups, each with children.
---Groups that probe empty are omitted entirely — an empty "agents" heading is
---worse than no heading.
---@return NavGroup[]
function M.tree()
  local groups = {}

  local agents = M.probe.agents()
  if #agents == 0 and M.probe.has_command("AutoAgents") then
    -- auto-agents is installed but the roster could not be read at all (no
    -- config file yet, e.g. a fresh install before the wizard has run). One
    -- entry that opens the panel is better than an empty group.
    groups[#groups + 1] = {
      id = "agents",
      label = "agents",
      children = {
        {
          id = "agents.panel",
          label = "open agents panel",
          detail = "no roster configured yet",
          action = { kind = "cmd", value = "AutoAgents" },
        },
      },
    }
  elseif #agents > 0 then
    -- Slot order, with slot 0 LAST.
    --
    -- The row's key IS the slot number, so `0` reaches admin and `2` reaches
    -- the agent in slot 2 — the same numbers the panel itself uses. v0.4.4
    -- numbered rows sequentially AND printed the slot in the label, giving
    -- every row two different numbers ("1.  0  admin"). Admin sits at the
    -- bottom because 0 after 1..n is how both panels order their control
    -- surface; leading with 0 would put the least-used row first.
    agents = vim.deepcopy(agents)
    table.sort(agents, function(x, y)
      local xa, ya = x.slot == 0, y.slot == 0
      if xa ~= ya then
        return ya
      end
      return x.slot < y.slot
    end)
    local children = {}
    for _, a in ipairs(agents) do
      children[#children + 1] = {
        key = tostring(a.slot),
        id = "agents." .. a.label,
        label = a.label,
        action = { kind = "cmd", value = "AutoAgentsFocus " .. a.slot },
      }
    end
    groups[#groups + 1] = { id = "agents", label = "agents", children = children }
  end

  local sections = M.probe.finder_sections()
  if #sections > 0 then
    -- auto-finder's registry is ZERO-based: `views/init.lua` assigns
    -- `number = i - 1`, so the FIRST configured section is 0 — its control
    -- surface, `config`, by the same "0 = control surface" convention
    -- auto-agents uses for admin.
    --
    -- v0.4.x dispatched the 1-based `ipairs` index, so every row went to the
    -- section BELOW the one it named and the last one was out of range. It
    -- looked harmless only because `auto-finder.focus` CLAMPS an out-of-range
    -- key to the default section instead of failing.
    --
    -- Dispatching by NAME rather than number removes the arithmetic entirely
    -- (`focus()` accepts either) and survives someone reordering
    -- `cfg.sections`. The number is still shown, because it is the key the
    -- panel's own 0..9 keymap uses.
    local rows = {}
    for i, name in ipairs(sections) do
      rows[#rows + 1] = { number = i - 1, name = name }
    end
    table.sort(rows, function(x, y)
      local xz, yz = x.number == 0, y.number == 0
      if xz ~= yz then
        return yz
      end
      return x.number < y.number
    end)
    local children = {}
    for _, r in ipairs(rows) do
      children[#children + 1] = {
        key = tostring(r.number),
        id = "finder." .. r.name,
        label = r.name,
        action = { kind = "cmd", value = "AutoFinderFocus " .. r.name },
      }
    end
    groups[#groups + 1] = { id = "finder", label = "finder", children = children }
  end

  local terms = M.probe.terminals()
  if #terms > 0 then
    local children = {}
    for _, n in ipairs(terms) do
      children[#children + 1] = {
        key = tostring(n),
        id = "terminal.T" .. n,
        label = ("T%d"):format(n),
        action = { kind = "cmd", value = ("AutoAgentsTerm focus %d"):format(n) },
      }
    end
    groups[#groups + 1] = { id = "terminal", label = "terminal", children = children }
  end

  -- Buffers sit above views: reaching a file you already have open is a far
  -- more frequent move than opening a log.
  local bufs = M.probe.buffers()
  if #bufs > 0 then
    local children = {}
    for i, b in ipairs(bufs) do
      children[#children + 1] = {
        -- Positional keys here, deliberately: a bufnr is not a stable, small
        -- number a user could memorise, and MRU order is the useful one.
        key = i <= 9 and tostring(i) or nil,
        id = "buffers." .. b.name,
        label = b.name,
        action = { kind = "cmd", value = "buffer " .. b.bufnr },
      }
      if i >= 9 then
        break
      end
    end
    groups[#groups + 1] = { id = "buffers", label = "buffers", children = children }
  end

  -- Views: the odds and ends that used to hang off F11/F12.
  local views = {}
  -- Only NO-ARGUMENT, user-facing views belong here. v0.4.0 built this list by
  -- probing for commands whose names looked view-ish, which put two wrong
  -- entries in it:
  --   * `AutoAgentsStatus` is a two-argument SETTER
  --     (`<slot|name> <idle|waiting|working>`) that agents call to report their
  --     own state. Invoked bare from the modal it hit its usage-error path.
  --   * `AutoAgentsDock` duplicated this modal; removed by Johno's call now
  --     that every slot is individually reachable under `agents`.
  -- Before adding a command here, read its definition and check it takes no
  -- required arguments and shows the user something.
  local candidates = {
    { cmd = "AutoAgentsDiffQueue", id = "views.diff-queue", label = "diff queue" },
    { cmd = "AutoCoreLog", id = "views.core-log", label = "auto-core log" },
  }
  for _, c in ipairs(candidates) do
    if M.probe.has_command(c.cmd) then
      views[#views + 1] = {
        id = c.id,
        label = c.label,
        action = { kind = "cmd", value = c.cmd },
      }
    end
  end
  if #views > 0 then
    groups[#groups + 1] = { id = "views", label = "views", children = views }
  end

  if M.probe.browser() then
    groups[#groups + 1] = {
      id = "browser",
      label = "browser",
      children = {
        {
          id = "browser.split",
          label = "open in tmux split pane",
          detail = "terminal-browser cannot render inside Neovim; a tmux pane can",
          action = {
            kind = "system",
            argv = {
              "terminal-browser", "open",
              "--split", M.BROWSER_SPLIT[1],
              "--size", M.BROWSER_SPLIT[2],
            },
          },
        },
      },
    }
  end

  return groups
end

---Flatten the tree to `id -> destination`, for resolving a user key bind.
---@return table<string, NavDest>
function M.by_id()
  local out = {}
  for _, g in ipairs(M.tree()) do
    for _, d in ipairs(g.children) do
      out[d.id] = d
    end
  end
  return out
end

---Execute a destination's action.
---@param dest NavDest
---@return boolean ok, string|nil err
function M.dispatch(dest)
  if type(dest) ~= "table" or type(dest.action) ~= "table" then
    return false, "not a navigable destination"
  end
  local a = dest.action
  if a.kind == "cmd" then
    local ok, err = pcall(vim.cmd, a.value)
    return ok, ok and nil or tostring(err)
  elseif a.kind == "system" then
    local ok, err = pcall(function()
      vim.system(a.argv, { text = true }, function(res)
        if res.code ~= 0 then
          vim.schedule(function()
            vim.notify(
              ("%s failed (exit %d)\n%s"):format(a.argv[1], res.code, res.stderr or ""),
              vim.log.levels.ERROR
            )
          end)
        end
      end)
    end)
    return ok, ok and nil or tostring(err)
  elseif a.kind == "fn" then
    local ok, err = pcall(a.value)
    return ok, ok and nil or tostring(err)
  end
  return false, "unknown action kind: " .. tostring(a.kind)
end

return M
