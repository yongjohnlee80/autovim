-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Map 'jk' to Escape in insert mode
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Worktree keymaps live in lua/plugins/worktree.lua under the lazy `keys =`
-- block of the worktree.nvim spec.

-- Override LazyVim's default <leader><leader> ("Find Files (Root Dir)") so it
-- only searches inside the worktrees shown under <leader>e (neo-tree-workspace).
-- Falls back to LazyVim's default when no repos are registered.
vim.keymap.set("n", "<leader><leader>", function()
  local dirs = require("utils.repos").worktree_paths()
  if #dirs == 0 then
    LazyVim.pick("files")()
    return
  end
  Snacks.picker.files({ dirs = dirs, hidden = true, ignored = true })
end, { desc = "Find Files (Workspace)" })
