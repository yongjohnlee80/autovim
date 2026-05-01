-- :TermSend <slot> <cmd>
--
-- Slots 1..4 → auto-agents.nvim playground terminals (paste-safe send,
-- marker-based lookup that survives :cd).
-- Slot 5     → codex via utils.term_send (kept for the safe/trusted toggle
-- machinery in plugin/codex.lua).
local CODEX_SLOT = 5

vim.api.nvim_create_user_command("TermSend", function(opts)
  -- Split on the first whitespace run so the command payload keeps its
  -- internal spacing intact (e.g. `echo  a   b` stays `echo  a   b` instead
  -- of being collapsed by vim.split).
  local slot_str, rest = vim.trim(opts.args):match("^(%S+)%s+(.+)$")
  if not slot_str or not rest then
    error("Usage: :TermSend <slot> <command>")
  end
  local slot = tonumber(slot_str)

  if slot == CODEX_SLOT then
    if not require("utils.term_send").send(slot, rest) then
      Snacks.notify.error(("Failed to send command to terminal %s"):format(tostring(slot)))
    end
    return
  end

  if not slot or slot < 1 or slot > 4 then
    error("TermSend: slot must be 1..4 (or 5 for codex), got " .. tostring(slot_str))
  end
  if not require("auto-agents.term").send(slot, rest) then
    Snacks.notify.error(("Failed to send command to T%d"):format(slot))
  end
end, {
  nargs = "+",
  desc = "Send a shell command to a terminal slot (1-4 via auto-agents, 5 via codex)",
})
