local term_send = require("utils.term_send")

local function send_to_slot(slot, cmd)
  if not term_send.send(slot, cmd) then
    Snacks.notify.error(("Failed to send command to terminal %s"):format(tostring(slot)))
  end
end

vim.api.nvim_create_user_command("TermSend", function(opts)
  -- Split on the first whitespace run so the command payload keeps its
  -- internal spacing intact (e.g. `echo  a   b` stays `echo  a   b` instead
  -- of being collapsed by vim.split).
  local slot, rest = vim.trim(opts.args):match("^(%S+)%s+(.+)$")
  if not slot or not rest then
    error("Usage: :TermSend <slot> <command>")
  end
  send_to_slot(tonumber(slot) or slot, rest)
end, {
  nargs = "+",
  desc = "Send a shell command to a terminal slot (1-4, or 5 for codex)",
})
