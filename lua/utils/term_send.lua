local M = {}

local MAX_SLOTS = 4
local CODEX_SLOT = 5

-- "safe" | "trusted" while slot 5 is running, nil when it's empty. Tracked
-- outside Snacks because safe/trusted share slot 5 but launch with different
-- command vectors, so Snacks would otherwise key them as two terminals.
local codex_mode = nil

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

local function codex_spec(mode, opts)
  opts = opts or {}
  local codex = require("utils.codex")
  local root = codex.project_root()
  local label = mode == "trusted" and "Codex (trusted)" or "Codex"
  local cmd = codex.terminal_command({
    trusted = mode == "trusted",
    force_new = opts.force_new,
  })
  return cmd,
    {
      count = CODEX_SLOT,
      cwd = root,
      win = win_opts(CODEX_SLOT, (" %s: %s "):format(label, codex.project_name(root))),
    }
end

-- Find whatever terminal currently sits in slot 5, regardless of the command
-- vector it was opened with. Snacks stamps `b:snacks_terminal = { id = count,
-- ... }` onto the buffer when the terminal is created, so a cross-mode lookup
-- (safe <-> trusted) is just a buffer scan.
local function find_codex_terminal()
  if not (Snacks and Snacks.terminal) then
    return nil
  end
  for _, term in ipairs(Snacks.terminal.list()) do
    local buf = term.buf
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local info = vim.b[buf].snacks_terminal
      if info and info.id == CODEX_SLOT then
        return term
      end
    end
  end
  return nil
end

local function close_codex_terminal()
  local term = find_codex_terminal()
  if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    vim.api.nvim_buf_delete(term.buf, { force = true })
  end
  codex_mode = nil
end

local function ensure_codex_available()
  local codex = require("utils.codex")
  if vim.fn.executable(codex.launcher_path()) == 1 or vim.fn.executable("codex") == 1 then
    return true
  end
  Snacks.notify.error("codex is not available on PATH")
  return false
end

function M.get(slot, opts)
  slot = validate_slot(slot)
  opts = opts or {}
  if slot == CODEX_SLOT then
    local term = find_codex_terminal()
    if term or opts.create == false then
      return term
    end
    -- No slot-5 terminal yet: boot a fresh safe one. Matches the F5 default.
    local cmd, topts = codex_spec("safe")
    topts.create = true
    codex_mode = "safe"
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

-- opts:
--   mode       - "safe" | "trusted"; when set, switch slot 5 to that mode
--                (killing the existing terminal if it's in the other mode).
--                When nil, just toggle visibility of the current slot-5
--                terminal, defaulting to safe mode when the slot is empty.
--   force_new  - start a new Codex session instead of resuming the last one.
function M.toggle_codex(opts)
  opts = opts or {}
  if not ensure_codex_available() then
    return nil
  end

  local requested = opts.mode
  local effective = requested or codex_mode or "safe"

  local mode_switch = requested and codex_mode and codex_mode ~= requested
  if mode_switch or opts.force_new then
    close_codex_terminal()
  end

  -- Snacks keys terminals by (cmd, cwd, env, count) — `Snacks.terminal.tid`
  -- in snacks/terminal.lua. Switching worktrees changes `project_root()` and
  -- therefore the cwd passed to `codex_spec`, so `Snacks.terminal.toggle`
  -- would hash to a fresh id and spawn a *second* slot-5 terminal. Since we
  -- want the single Codex instance to persist across worktrees, look up the
  -- existing slot-5 buffer first (count-keyed, cwd-agnostic) and just
  -- toggle its visibility. Only fall through to Snacks when slot 5 is
  -- actually empty — e.g. first launch, or after `close_codex_terminal`
  -- above for a mode switch / `force_new`.
  local existing = find_codex_terminal()
  if existing then
    codex_mode = codex_mode or effective
    return existing:toggle()
  end

  local cmd, topts = codex_spec(effective, { force_new = opts.force_new })
  codex_mode = effective
  return Snacks.terminal.toggle(cmd, topts)
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
