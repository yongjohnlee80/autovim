-- AutoVim self-update keymap.
--
-- <leader>aU (and :AutoVimUpdate [1-4]) runs `~/.config/nvim/update.sh`
-- inside one of the auto-agents playground terminals (T1..T4). The
-- terminal stays open so the user can watch the rsync + Lazy! sync.
-- Picks the slot via `vim.ui.select` when invoked without an
-- argument; pass `:AutoVimUpdate 2` to skip the prompt.
--
-- After update.sh finishes the user must restart nvim (or `:Lazy
-- reload`) to pick up the new tracked-file content — update.sh writes
-- to disk while the running nvim has the old modules loaded in
-- memory.

local function run_update_in_slot(slot)
  local script = vim.fn.stdpath("config") .. "/update.sh"
  if vim.fn.executable(script) ~= 1 then
    vim.notify(
      "update.sh not found or not executable at " .. script,
      vim.log.levels.ERROR,
      { title = "AutoVim" }
    )
    return
  end

  local ok, term = pcall(require, "auto-agents.term")
  if not ok then
    vim.notify(
      "auto-agents.term not available — load the panel once via <F5> then retry",
      vim.log.levels.ERROR,
      { title = "AutoVim" }
    )
    return
  end

  if not term.send(slot, script) then
    vim.notify(
      ("Failed to send update.sh to T%d"):format(slot),
      vim.log.levels.ERROR,
      { title = "AutoVim" }
    )
  end
end

local function pick_slot_and_run()
  vim.ui.select({ 1, 2, 3, 4 }, {
    prompt = "AutoVim update — which playground terminal?",
    format_item = function(s) return "T" .. s end,
  }, function(choice)
    if choice then run_update_in_slot(choice) end
  end)
end

vim.api.nvim_create_user_command("AutoVimUpdate", function(opts)
  local n = tonumber(vim.trim(opts.args or ""))
  if n and n >= 1 and n <= 4 then
    run_update_in_slot(n)
  else
    pick_slot_and_run()
  end
end, {
  nargs = "?",
  desc = "AutoVim: run update.sh in playground terminal T1..T4 (prompts if no slot given)",
})

vim.keymap.set("n", "<leader>aU", pick_slot_and_run, {
  desc = "AutoVim: run update.sh in a playground terminal",
})