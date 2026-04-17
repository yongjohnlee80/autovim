-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Map 'jk' to Escape in insert mode
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Worktree switcher. Module captures the startup cwd as "root" on first require.
-- <leader>gw  → pick a worktree under root and :cd into it
-- <leader>gW  → :cd back to the original root
-- Existing :term buffers keep their own pwd (independent child processes).
local worktree = require("utils.worktree")
vim.keymap.set("n", "<leader>gw", worktree.pick, { desc = "Worktree: switch" })
vim.keymap.set("n", "<leader>gW", worktree.home, { desc = "Worktree: back to root" })
