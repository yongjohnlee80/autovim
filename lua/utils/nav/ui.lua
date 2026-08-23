-- The centred navigation modal (`<C-g>`, also `<F6>`).
--
-- Deliberately a plain `nvim_open_win` float rather than a picker: the modal
-- needs single-key dispatch, a `*` bind gesture, and two levels of drill-down,
-- and bending a fuzzy picker into that shape costs more than 200 lines of
-- window code. It also means the modal works before any picker plugin loads.
--
-- Keys:
--   1-9 / a-z   jump straight to a numbered row or a user-bound letter
--   j / k       move, <CR> activate, h / <BS> back up a level
--   *           assign a letter to the highlighted destination
--   q / <Esc>   close
--
-- The user-assigned letters are per WORKSPACE (see `nav.binds`), so the top
-- level names the workspace they belong to.

local registry = require("utils.nav.registry")
local binds = require("utils.nav.binds")

local M = {}

M.NS = vim.api.nvim_create_namespace("autovim_nav")

-- Live modal state. `rows` is parallel to the buffer's lines, so the cursor
-- line indexes it directly — the same discipline the finder panel uses.
M._state = nil

local function close()
  local st = M._state
  M._state = nil
  if not st then
    return
  end
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    pcall(vim.api.nvim_win_close, st.win, true)
  end
  if st.buf and vim.api.nvim_buf_is_valid(st.buf) then
    pcall(vim.api.nvim_buf_delete, st.buf, { force = true })
  end
end

M.close = close

function M.is_open()
  local st = M._state
  return st ~= nil and st.win ~= nil and vim.api.nvim_win_is_valid(st.win)
end

---Rows for the current level.
---@return table[] rows, string title
local function build_rows(group_id)
  local tree = registry.tree()
  local rows = {}

  if group_id then
    for _, g in ipairs(tree) do
      if g.id == group_id then
        for i, d in ipairs(g.children) do
          rows[#rows + 1] = {
            -- The destination's OWN key when it has one (a panel slot number),
            -- else the position. v0.4.4 always used the position AND printed
            -- the slot inside the label, so every agent/finder row showed two
            -- different numbers.
            key = d.key or (i <= 9 and tostring(i) or nil),
            label = d.label,
            dest = d,
            bound = binds.key_for(d.id),
          }
        end
        return rows, "navigate → " .. g.label
      end
    end
    return rows, "navigate"
  end

  -- Top level: the groups, then every resolvable user bind.
  for i, g in ipairs(tree) do
    rows[#rows + 1] = {
      key = i <= 9 and tostring(i) or nil,
      label = g.label,
      group = g.id,
      count = #g.children,
    }
  end

  local by_id = registry.by_id()
  local bound = binds.load()
  local letters = vim.tbl_keys(bound)
  table.sort(letters)
  for _, letter in ipairs(letters) do
    local dest = by_id[bound[letter]]
    -- Silently skip binds whose destination is gone (plugin disabled, agent
    -- renamed). The bind stays on disk; see binds.lua.
    if dest then
      rows[#rows + 1] = { key = letter, label = dest.label, dest = dest, is_bind = true }
    end
  end

  -- Name the workspace at the top level: the letter shortcuts below the groups
  -- belong to THIS workspace only (`nav.binds`), and "my letter is missing"
  -- is otherwise indistinguishable from "my bind was lost".
  local tail = vim.fn.fnamemodify(binds.workspace(), ":t")
  return rows, tail ~= "" and ("navigate · " .. tail) or "navigate"
end

local function render()
  local st = M._state
  if not st then
    return
  end
  local rows, title = build_rows(st.group)
  st.rows = rows

  local lines = {}
  for _, r in ipairs(rows) do
    local key = r.key and (r.key .. ".") or "  "
    local suffix = ""
    if r.group then
      suffix = ("  (%d)"):format(r.count)
    elseif r.bound then
      suffix = ("   [%s]"):format(r.bound)
    end
    lines[#lines + 1] = (" %-3s %s%s"):format(key, r.label, suffix)
  end
  if #lines == 0 then
    lines = { " (nothing to navigate to)" }
  end

  local hint = st.group and " <CR> go · h/<BS> back · * bind · q close"
    or " <CR> go · * bind letter · q close"
  lines[#lines + 1] = ""
  lines[#lines + 1] = hint

  vim.bo[st.buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
  vim.bo[st.buf].modifiable = false

  -- Keep the cursor on a selectable row.
  local target = math.max(1, math.min(st.cursor or 1, #rows))
  st.cursor = target
  if #rows > 0 and vim.api.nvim_win_is_valid(st.win) then
    pcall(vim.api.nvim_win_set_cursor, st.win, { target, 0 })
  end
  pcall(vim.api.nvim_win_set_config, st.win, { title = " " .. title .. " " })

  vim.api.nvim_buf_clear_namespace(st.buf, M.NS, 0, -1)
  for i, r in ipairs(rows) do
    if r.key then
      vim.api.nvim_buf_set_extmark(st.buf, M.NS, i - 1, 0, {
        end_col = math.min(4, #lines[i]),
        hl_group = r.is_bind and "DiagnosticOk" or "Title",
      })
    end
  end
  vim.api.nvim_buf_set_extmark(st.buf, M.NS, #lines - 1, 0, { line_hl_group = "Comment" })
end

---@param row table
local function activate(row)
  if not row then
    return
  end
  if row.group then
    M._state.group = row.group
    M._state.cursor = 1
    render()
    return
  end
  local dest = row.dest
  close()
  if not dest then
    return
  end

  -- Dispatch on the NEXT tick, not inline after `close()`.
  --
  -- Closing this float moves focus to a non-float window, which fires WinEnter,
  -- and `auto-agents.term.focus` answers that by queueing `vim.schedule(hide_all)`
  -- to hide every T1..T4 float. Dispatching inline therefore opened the terminal
  -- BEFORE that queued hide ran, and the hide then closed it again — the
  -- "terminal flashes open then disappears" bug.
  --
  -- `vim.schedule` is FIFO, so deferring puts us behind the already-queued
  -- hide: it drains first (hiding nothing, since nothing is open yet), then we
  -- open. Harmless for the non-float destinations, which the auto-hide ignores.
  vim.schedule(function()
    local ok, err = registry.dispatch(dest)
    if not ok then
      vim.notify(("navigate: %s failed — %s"):format(dest.id, tostring(err)), vim.log.levels.ERROR)
    end
  end)
end

local function current_row()
  local st = M._state
  if not st or not st.rows then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(st.win)[1]
  return st.rows[line], line
end

---The `*` gesture: ask for a letter and bind it to the highlighted destination.
local function bind_here()
  local row = current_row()
  if not row or not row.dest then
    vim.notify("navigate: only a destination can take a shortcut (not a group)", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = ("shortcut letter for %s: "):format(row.dest.id) }, function(key)
    if not key or key == "" then
      return
    end
    local ok, err = binds.bind(key, row.dest.id)
    if not ok then
      vim.notify("navigate: " .. tostring(err), vim.log.levels.WARN)
      return
    end
    vim.notify(("navigate: `%s` → %s"):format(key, row.dest.id))
    if M.is_open() then
      render()
    end
  end)
end

function M.open()
  if M.is_open() then
    close()
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "autovim-nav"

  local width = math.min(56, math.max(34, math.floor(vim.o.columns * 0.35)))
  local height = 16
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " navigate ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = true

  M._state = { buf = buf, win = win, group = nil, cursor = 1, rows = {} }
  render()

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("q", close)
  map("<Esc>", close)
  map("<CR>", function()
    activate((current_row()))
  end)
  map("*", bind_here)
  map("h", function()
    if M._state and M._state.group then
      M._state.group = nil
      M._state.cursor = 1
      render()
    end
  end)
  map("<BS>", function()
    if M._state and M._state.group then
      M._state.group = nil
      M._state.cursor = 1
      render()
    end
  end)

  -- Direct dispatch. A digit picks the Nth row of the CURRENT level; a letter
  -- resolves through the user's binds, from either level, so a shortcut works
  -- even while drilled into an unrelated group.
  -- 0..9 select by the row's KEY, so a slot number reaches its own slot: `0`
  -- is admin / the config section, not "the tenth row". Falls back to position
  -- for groups whose rows carry no explicit key (views, browser).
  for d = 0, 9 do
    local digit = tostring(d)
    map(digit, function()
      local st = M._state
      if not st or not st.rows then
        return
      end
      for _, r in ipairs(st.rows) do
        if r.key == digit then
          activate(r)
          return
        end
      end
      local n = tonumber(digit)
      if n and n >= 1 then
        activate(st.rows[n])
      end
    end)
  end
  -- RESERVED is what keeps this loop from clobbering the modal's own letter
  -- maps. `h` used to be missing from it, so the back mapping above was
  -- overwritten here by a bind lookup that resolved to nothing — the modal
  -- advertised `h back` while only `<BS>` worked.
  for c = string.byte("a"), string.byte("z") do
    local letter = string.char(c)
    if not binds.RESERVED[letter] then
      map(letter, function()
        local id = binds.load()[letter]
        if not id then
          return
        end
        activate({ dest = registry.by_id()[id] })
      end)
    end
  end

  -- Closing on focus loss keeps the modal from lingering behind other windows.
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(close)
    end,
  })
end

return M
