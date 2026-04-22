local M = {}

local MAX_SLOTS = 4
local CODEX_SLOT = 5

local function win_opts(slot, title)
  return {
    width = 0.76,
    height = 0.76,
    row = 0.02 + ((slot - 1) * 0.025),
    col = 0.04 + ((slot - 1) * 0.03),
    title = title,
    title_pos = "center",
  }
end

local function validate_slot(slot)
  slot = tonumber(slot)
  -- Slot 5 is Codex. Accepting it here lets :TermSend 5 <cmd> route through
  -- the same send() path as the numbered shells so Claude can drive Codex the
  -- same way it drives 1-4.
  if slot == CODEX_SLOT then
    return slot
  end
  if not slot or slot < 1 or slot > MAX_SLOTS or slot ~= math.floor(slot) then
    error(
      ("term_send: slot must be an integer in 1..%d or %d (codex), got %s"):format(
        MAX_SLOTS,
        CODEX_SLOT,
        tostring(slot)
      )
    )
  end
  return slot
end

-- snacks.nvim keys terminals by (cmd, cwd, count). The codex terminal is
-- spawned with a different cmd and cwd than a bare shell, so looking it up
-- with vim.o.shell (what slots 1-4 use) would miss and silently create a
-- second terminal on slot 5. This helper builds the exact spec used by the
-- initial toggle so get()/send() resolve to the same object.
local function codex_term_spec()
  local codex = require("utils.codex")
  local root = codex.project_root()
  return codex.terminal_command(), {
    count = CODEX_SLOT,
    cwd = root,
    win = win_opts(CODEX_SLOT, (" Codex: %s "):format(codex.project_name(root))),
  }
end

function M.get(slot, opts)
  slot = validate_slot(slot)
  opts = opts or {}
  if slot == CODEX_SLOT then
    local cmd, topts = codex_term_spec()
    topts.create = opts.create ~= false
    return Snacks.terminal.get(cmd, topts)
  end
  return Snacks.terminal.get(vim.o.shell, {
    count = slot,
    create = opts.create ~= false,
    win = win_opts(slot, (" Terminal %d "):format(slot)),
  })
end

function M.toggle(slot)
  slot = validate_slot(slot)
  if slot == CODEX_SLOT then
    return M.toggle_codex()
  end
  return Snacks.terminal.toggle(vim.o.shell, {
    count = slot,
    win = win_opts(slot, (" Terminal %d "):format(slot)),
  })
end

function M.toggle_codex(opts)
  opts = opts or {}
  if vim.fn.executable("codex") ~= 1 then
    Snacks.notify.error("codex is not available on PATH")
    return nil
  end

  local _, topts = codex_term_spec()
  local codex = require("utils.codex")
  -- force_new bypasses the `codex resume --last` shell wrapper to get a fresh
  -- session. Subsequent send()s route via codex_term_spec()'s resume command,
  -- so after force_new the lookup will miss until the user toggles again.
  return Snacks.terminal.toggle(codex.terminal_command(opts), topts)
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
M.CODEX_SLOT = CODEX_SLOT

return M
