-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Map 'jk' to Escape in insert mode
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Worktree keymaps live in lua/plugins/worktree.lua under the lazy `keys =`
-- block of the worktree.nvim spec.

-- ── Central navigation modal (requirements 7 + 8) ────────────────────────
--
-- Wired here, NOT as a spec in `lua/plugins/`, and that is deliberate: lazy
-- dedupes local plugins by `dir`, so a second pseudo-plugin declaring
-- `dir = vim.fn.stdpath("config")` is silently DROPPED — `theme-picker.lua`
-- already claims that dir. (That is not hypothetical: it is why the Omarchy
-- theme hot-reload never actually ran on the old `omarchy` branch.) A keymap
-- and two commands are config, not a plugin, so they belong here where nothing
-- can drop them.
--
-- `<C-g>` replaces F-key navigation as the primary surface. F-keys are
-- unreliable across terminal emulators, tmux and SSH; the F-keys stay bound in
-- `lua/plugins/auto-agents.lua` so existing muscle memory keeps working.
--
-- `<C-g>` over the initially-considered `<C-y>`: `<C-y>` is a native motion
-- (scroll up one line) that `smooth-scroll.lua` already animates, so taking it
-- would shadow a real editing key. `<C-g>` natively only prints the file's info
-- line, and nothing in AutoVim binds it.
--
-- Logic lives in `lua/utils/nav/{registry,binds,ui}.lua` and is unit-tested by
-- `tests/nav-modal.lua`.
vim.api.nvim_create_user_command("AutovimNav", function()
  require("utils.nav.ui").open()
end, { desc = "Open the central navigation modal" })

vim.api.nvim_create_user_command("AutovimNavUnbind", function(opts)
  local key = opts.fargs[1]
  local ok, err = require("utils.nav.binds").unbind(key)
  vim.notify(
    ok and ("navigate: unbound `%s`"):format(key) or ("navigate: " .. tostring(err)),
    ok and vim.log.levels.INFO or vim.log.levels.WARN
  )
end, { nargs = 1, desc = "Remove a navigation-modal shortcut letter" })

-- Normal AND terminal mode: the modal's whole point is getting out of an agent
-- slot or a playground terminal without reaching for a function key, and those
-- buffers are in terminal mode.
vim.keymap.set({ "n", "t" }, "<C-g>", function()
  require("utils.nav.ui").open()
end, { desc = "Navigate (central modal)" })
