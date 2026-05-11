-- AutoVim user keymaps.
--
-- Runs AFTER `lua/config/keymaps.lua`, so a re-binding here wins over
-- the stock one. For plugin keymaps declared in a `keys = { ... }`
-- lazy spec, override via a custom plugin spec instead (see
-- `lua/custom/plugins/example.lua`).
--
-- Stock keymap namespaces (preserve these unless you mean to retire them):
--   <leader>a*     auto-agents
--   <F5> / <F6> / <F12>  auto-agents
--   <leader>r*     remote-sync
--   <leader>gq / gQ remote-sync
--   <leader>gw / gW / gA / gR / gC / gc / gt  worktree.nvim
--   <leader>m*     markdown / md-harpoon
--   <leader>R*     REST (kulala)
--   <leader>d*     Go debugging (gobugger)
--   <F7>..<F10>    Go debug stepping

local map = vim.keymap.set

-- Examples (commented out):

-- map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save buffer" })
-- map("n", "<C-s>",     "<cmd>w<cr>", { desc = "Save buffer" })
-- map("i", "jk",        "<Esc>",      { desc = "Exit insert" })

-- Disable a stock keymap (give it an empty rhs OR set to <Nop>):
-- vim.keymap.del("n", "<leader>x")
