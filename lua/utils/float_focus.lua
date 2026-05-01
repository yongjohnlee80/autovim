-- Floating-window focus/hide helper for the persistent Snacks-terminal floats
-- (T1..T5 + any user-invoked `Snacks.terminal.toggle` like lazysql / lazygit).
--
-- Two distinct behaviors live here:
--
--   1. `focus_or_hide_slot(slot)` — the new F1..F5 dispatch. Replaces the
--      plain `term:toggle()` binding so that pressing Fn when the matching
--      terminal is *visible but not focused* moves focus to it instead of
--      closing it. Only the focused-and-pressed case still hides.
--
--   2. `hide_all_tracked_floats()` + a `WinEnter` autocmd — when the user
--      leaves the float group entirely (moves into main buffer, neo-tree,
--      the claudecode split, etc.), hide every Snacks-terminal float so the
--      main splits aren't visually overlaid. Non-Snacks floats (telescope,
--      blink.cmp completion, LSP hover, flash labels) are never touched;
--      they're transient by design.

local M = {}

local TermSend = require("utils.term_send")

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

-- Run the slot's first-launch path (create + show) using the existing
-- term_send entry points, which already encode the safe/trusted Codex
-- handling for slot 5.
local function open_slot(slot)
  if slot == TermSend.CODEX_SLOT then
    return TermSend.toggle_codex()
  end
  return TermSend.toggle(slot)
end

-- Hide a slot by round-tripping through term:toggle(). We avoid term:hide()
-- here to stay consistent with the path Snacks takes when the user presses
-- Fn on a focused terminal today — keeps the "toggle" bookkeeping happy.
local function hide_slot_term(term)
  if not term then
    return
  end
  if type(term.toggle) == "function" then
    pcall(term.toggle, term)
  elseif type(term.hide) == "function" then
    pcall(term.hide, term)
  end
end

-- Press-Fn dispatch:
--   - no terminal yet              → open it (create + focus)
--   - terminal hidden              → re-open it and force focus
--   - terminal visible, focused    → hide
--   - terminal visible, unfocused  → focus it (leave other floats alone)
function M.focus_or_hide_slot(slot)
  local term = TermSend.get(slot, { create = false })
  if not term then
    return open_slot(slot)
  end

  local win = find_win_for_buf(term.buf)
  if not win then
    open_slot(slot)
    -- Some spawn paths (especially the Codex mode-switch branch) may leave
    -- the new window without focus. Force it just in case.
    local new_win = find_win_for_buf(term.buf)
    if new_win and vim.api.nvim_win_is_valid(new_win) then
      pcall(vim.api.nvim_set_current_win, new_win)
    end
    return
  end

  if vim.api.nvim_get_current_win() == win then
    hide_slot_term(term)
  else
    pcall(vim.api.nvim_set_current_win, win)
  end
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
