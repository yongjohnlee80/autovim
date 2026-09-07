-- Extend LazyVim's bufferline offsets so the auto-finder panel gets the
-- same "no tabs over me" treatment.
--
-- After auto-finder.nvim's v0.1.3 fork-neotree severance, the panel's
-- file/repo sections use filetype `auto-finder` (was `neo-tree`); the
-- config (REPL) section keeps `auto-finder-config`. Both need offset
-- entries so bufferline reserves the panel's column band on the left
-- instead of painting tabs over our winbar. LazyVim's default offsets
-- list (which only knows about `neo-tree`) doesn't cover us once the
-- fork renamed the filetype.
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
      -- `text` is a FUNCTION, so the heading names the checkout you are in
      -- rather than repeating the panel's own name at you (Johno,
      -- 2026-09-08). bufferline calls it on every tabline redraw and accepts
      -- a function here (`offset.lua`: `if type(text) == "function" then text
      -- = text() end`), so the resolution is cached in `utils.panel_heading`
      -- against the scope directory — the tabline redraws far too often to
      -- spend three `git rev-parse` reads a frame.
      --
      -- Truncation is ours, not bufferline's. bufferline would cut from the
      -- right of the whole string, which keeps the useless half — "auto-fin…"
      -- — and drops the repo and branch. `panel_heading.heading` sheds the
      -- "auto-finder: " prefix FIRST and only then ellipsizes the scope.
      local function heading()
        local ok, ph = pcall(require, "utils.panel_heading")
        -- A literal fallback, deliberately: this runs inside a tabline
        -- redraw, where an error would either blank the tabline or spam
        -- notifications on every frame.
        if not ok then return "auto-finder" end
        local ok_text, text = pcall(ph.text)
        return ok_text and text or "auto-finder"
      end
      table.insert(opts.options.offsets, {
        filetype = "auto-finder-config",
        text = heading,
        highlight = "Directory",
        text_align = "left",
      })
      table.insert(opts.options.offsets, {
        filetype = "auto-finder",
        text = heading,
        highlight = "Directory",
        text_align = "left",
      })
      -- NOTE: the dbase section used to mount nvim-dbee's drawer (filetype
      -- "dbee") into the panel window; dbee was retired in v0.4.0 and autodb's
      -- explorer stamps the canonical panel filetype. auto-finder >= v0.2.64
      -- re-stamps that buffer filetype "auto-finder", so the entry
      -- above already covers dbase — no separate "dbee" offset needed.
      -- Function-form click commands bypass bufferline's vim.cmd
      -- handler entirely (commands.lua:41-43 — `if type(command) ==
      -- "function" then command(id) end`), so winfixbuf doesn't get a
      -- chance to error. We do the buffer switch ourselves in a
      -- safe window.
      opts.options.left_mouse_command = safe_buffer_click
    end,
  },
}
