-- WinEnter-driven auto-hide for the user-invoked `Snacks.terminal.toggle`
-- floats (lazysql, lazygit, etc.). When the user leaves the float group
-- entirely (moves into main buffer, neo-tree, the claudecode split, etc.),
-- hide every Snacks-terminal float so the main splits aren't visually
-- overlaid. Non-Snacks floats (telescope, blink.cmp completion, LSP hover,
-- flash labels) are never touched; they're transient by design.
--
-- F1..F4 playground terminals and F5 panel are owned by auto-agents.nvim,
-- which manages its own focus/hide lifecycle (the marker-skip below leaves
-- those floats alone).

local M = {}

local function is_float(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local cfg = vim.api.nvim_win_get_config(win)
  return cfg.relative ~= nil and cfg.relative ~= ""
end

local function find_win_for_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  return nil
end

-- Hide every Snacks-terminal float currently visible in this tab page.
-- We scope on "is a Snacks terminal" rather than "is any float" to avoid
-- clobbering transient plugin floats (telescope pickers, completion menus,
-- signature help popups, etc.) that the user explicitly just opened.
--
-- Skips auto-agents.nvim sub-agent floats (slots 5..9, marked with
-- `b:auto_agents_slot`) — they have their own auto-hide machinery that
-- handles the same WinEnter race more carefully (re-checks current focus
-- inside the deferred schedule). Without this skip, our hide_all would
-- close auto-agents floats immediately after they're summoned via
-- <leader>a5..9.
function M.hide_all_tracked_floats()
  if not (Snacks and Snacks.terminal) then
    return
  end
  for _, term in ipairs(Snacks.terminal.list()) do
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      if vim.b[term.buf].auto_agents_slot then
        -- Owned by auto-agents.nvim — let it manage its own float lifecycle.
      else
        local win = find_win_for_buf(term.buf)
        if win and is_float(win) then
          if type(term.hide) == "function" then
            pcall(term.hide, term)
          else
            pcall(term.toggle, term)
          end
        end
      end
    end
  end
end

-- Install the WinEnter autocmd. Re-entrant: nvim_create_augroup with
-- clear=true wipes any prior install, so re-sourcing is safe.
function M.install_auto_hide()
  local group = vim.api.nvim_create_augroup("FloatFocus_AutoHide", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      -- Still inside any floating window → we're in the "float group",
      -- don't disturb the others. This covers jumping between T1..T5 /
      -- lazysql / lazygit as well as transient plugin floats.
      if is_float(vim.api.nvim_get_current_win()) then
        return
      end
      -- Moved into a non-float (main buffer, claudecode split, neo-tree,
      -- any other split). Defer the hide so Snacks finishes whatever
      -- window operation triggered the WinEnter before we start closing
      -- things.
      vim.schedule(M.hide_all_tracked_floats)
    end,
  })
end

return M
