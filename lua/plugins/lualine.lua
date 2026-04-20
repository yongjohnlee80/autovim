-- Prepend the repo+worktree-marker component (provided by worktree.nvim) to
-- lualine's section_b so the statusline shows `repo │ branch`, with a
-- trailing `(wt)` when the cwd is a linked git worktree.

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_b, 1, {
        require("worktree").lualine_component,
      })
      return opts
    end,
  },
}
