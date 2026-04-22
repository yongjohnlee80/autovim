local M = {}

local MAX_SLOTS = 4

local function win_opts(slot)
  return {
    width = 0.78,
    height = 0.78,
    row = 0.04 + ((slot - 1) * 0.03),
    col = 0.06 + ((slot - 1) * 0.04),
    title = (" Terminal %d "):format(slot),
    title_pos = "center",
  }
end

local function validate_slot(slot)
  slot = tonumber(slot)
  if not slot or slot < 1 or slot > MAX_SLOTS or slot ~= math.floor(slot) then
    error(("term_send: slot must be an integer in 1..%d, got %s"):format(MAX_SLOTS, tostring(slot)))
  end
  return slot
end

function M.get(slot, opts)
  slot = validate_slot(slot)
  opts = opts or {}
  return Snacks.terminal.get(vim.o.shell, {
    count = slot,
    create = opts.create ~= false,
    win = win_opts(slot),
  })
end

function M.toggle(slot)
  slot = validate_slot(slot)
  return Snacks.terminal.toggle(vim.o.shell, {
    count = slot,
    win = win_opts(slot),
  })
end

function M.send(slot, cmd, opts)
  slot = validate_slot(slot)
  opts = opts or {}
  if type(cmd) ~= "string" or cmd == "" then
    error("term_send: cmd must be a non-empty string")
  end

  local term = M.get(slot, { create = true })
  if not term then
    return false
  end

  if opts.show ~= false then
    term:show()
  end

  local chan = vim.b[term.buf].terminal_job_id
  if not chan then
    return false
  end

  local suffix = opts.submit == false and "" or "\n"
  vim.api.nvim_chan_send(chan, cmd .. suffix)
  return true
end

M.MAX_SLOTS = MAX_SLOTS

return M
