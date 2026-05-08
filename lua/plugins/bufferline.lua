-- Extend LazyVim's bufferline offsets so the auto-finder panel gets the
-- same "no tabs over me" treatment neo-tree already has. The config
-- section uses filetype `auto-finder-config`; neo-tree's filetype keeps
-- the LazyVim default and we just append our own entry next to it.
-- Click-into-buffer that survives `winfixbuf`. Without this, clicking a
-- bufferline tab while focused on the auto-finder or auto-agents panel
-- raises E1513 because vim refuses to swap the panel's buffer. We
-- intercept the click, jump to the first non-winfixbuf, non-floating
-- sibling window (or split a new one if none exist), and run the
-- buffer switch there instead.
local function pick_non_panel_window()
  local cur = vim.api.nvim_get_current_win()
  -- Prefer a window that isn't winfixbuf and isn't a panel-class
  -- filetype. Iterate in reverse so we tend to land on the rightmost
  -- main editor window when both auto-finder (left) and the agent
  -- panel (right) are open.
  local wins = vim.api.nvim_list_wins()
  for i = #wins, 1, -1 do
    local w = wins[i]
    if w ~= cur then
      local ok, fixed = pcall(function() return vim.wo[w].winfixbuf end)
      if ok and not fixed then
        local cfg_ok, cfg = pcall(vim.api.nvim_win_get_config, w)
        if cfg_ok and cfg.relative == "" then
          return w
        end
      end
    end
  end
  -- Nothing suitable — split a new window. `aboveleft new` opens a
  -- horizontal split with a fresh empty buffer above; `aboveleft vnew`
  -- would also work but vertical might compete with the panels'
  -- winfixwidth. The new window's buffer is empty, so the caller's
  -- :buffer N just replaces it cleanly.
  vim.cmd("aboveleft new")
  return vim.api.nvim_get_current_win()
end

local function safe_buffer_click(id)
  local cur = vim.api.nvim_get_current_win()
  local fixed = false
  pcall(function() fixed = vim.wo[cur].winfixbuf end)
  if fixed then
    local target = pick_non_panel_window()
    pcall(vim.api.nvim_set_current_win, target)
  end
  -- Now we're in a window that accepts a buffer switch.
  vim.cmd("buffer " .. id)
end

return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.offsets = opts.options.offsets or {}
      table.insert(opts.options.offsets, {
        filetype = "auto-finder-config",
        text = "auto-finder",
        highlight = "Directory",
        text_align = "left",
      })
      -- Function-form click commands bypass bufferline's vim.cmd
      -- handler entirely (commands.lua:41-43 — `if type(command) ==
      -- "function" then command(id) end`), so winfixbuf doesn't get a
      -- chance to error. We do the buffer switch ourselves in a
      -- safe window.
      opts.options.left_mouse_command = safe_buffer_click
    end,
  },
}
