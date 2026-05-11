-- Prepend the repo+worktree-marker component (provided by worktree.nvim) to
-- lualine's section_b so the statusline shows `repo │ branch`, with a
-- trailing `(wt)` when the cwd is a linked git worktree.
--
-- Append a memory-usage component to section_y so the statusline
-- reflects the running nvim's RSS. Cheap: `vim.uv.resident_set_memory()`
-- on platforms that support it, falling back to `collectgarbage("count")`
-- (Lua heap only) otherwise. Refreshed lazily per redraw via lualine's
-- normal eval cycle — no timer.

local function memory_component()
  local rss_ok, rss = pcall(function()
    return (vim.uv or vim.loop).resident_set_memory()
  end)
  if rss_ok and type(rss) == "number" and rss > 0 then
    local mb = rss / (1024 * 1024)
    return string.format("\u{f1c0} %.0fMB", mb)   -- nf-fa-database
  end
  -- Fallback: Lua heap only (KB → MB). Reasonable proxy on systems
  -- where libuv's RSS query isn't available.
  local kb = collectgarbage("count")
  return string.format("\u{f1c0} %.1fMB", kb / 1024)
end

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_b, 1, {
        require("worktree").lualine_component,
      })
      table.insert(opts.sections.lualine_y, 1, {
        memory_component,
        cond = function() return vim.o.columns >= 100 end,  -- hide on narrow windows
      })
      return opts
    end,
  },
}
