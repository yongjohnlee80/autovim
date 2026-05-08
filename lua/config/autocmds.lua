-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

require("utils.float_focus").install_auto_hide()

-- Markdown: disable conceal so GFM tables stay visually aligned.
-- LazyVim sets conceallevel=2 globally, and treesitter's markdown_inline
-- query conceals inline markup (** ` * _ ~~). Formatters (prettier) align
-- the RAW source — counting those markers — but conceal hides them at
-- display time, so any cell with bold/code/italic renders narrower than the
-- source and the column pipes stop lining up. nvim can't replace the markers
-- with equal-width spaces (it collapses each multi-char delimiter like ** or
-- ~~ to a single conceal char), so short of a render plugin the clean fix is
-- to turn conceal off for markdown. conceallevel is window-local, so set it
-- per-window on the markdown FileType.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("UserMarkdownConceal", { clear = true }),
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})
