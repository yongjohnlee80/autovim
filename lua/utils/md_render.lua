-- Three independent md-render preview slots — left / middle / right —
-- driven by `<leader>ma` / `<leader>ms` / `<leader>md`. Each slot owns its
-- own FloatWin instance, scratch buffer, and "last source" pointer, so the
-- user can render up to three different markdown files at once and compare
-- them side-by-side.
--
-- Why this exists: md-render's bundled `MdPreview.show()` keeps a single
-- module-local FloatWin (preview.lua:7) and `close_if_valid`s it on every
-- call, so calling show() three times can't yield three coexisting floats.
-- The plugin's library-level API (FloatWin / display_utils /
-- preview.build_content) is the supported escape hatch for embedding,
-- per the README's "Usage as a library" section. We use those to
-- replicate show()'s rendering pipeline with per-slot state.
--
-- Notable differences from `MdPreview.show()`:
--   * `auto_close = false` on every slot's FloatWin so floats persist
--     while the user moves focus between source buffers and other floats.
--   * Geometry is fixed to a left/middle/right grid (each ~1/3 of
--     `vim.o.columns`) instead of centered on the screen, so 3 slots fit.
--   * Cursor sync-back to source on close is intentionally dropped —
--     with three slots open against different source buffers, syncing
--     all three back is more confusing than helpful.

local M = {}

-- Panel width bounds. Adjust here to change the per-slot floor/ceiling.
-- The float clamps to [MIN_PANEL_WIDTH, MAX_PANEL_WIDTH]; content wraps
-- at CONTENT_INTERIOR_WIDTH (= MAX_PANEL_WIDTH - 4 to leave room for the
-- rounded border + a 1-col right-edge margin).
local MIN_PANEL_WIDTH = 80
local MAX_PANEL_WIDTH = 120
local CONTENT_INTERIOR_WIDTH = MAX_PANEL_WIDTH - 4

local SLOT_SIDE = { a = "left", s = "middle", d = "right" }

---@class MdRenderSlotState
---@field float_win MdRender.FloatWin
---@field source_bufnr integer? bufnr last rendered into this slot

---@type table<string, MdRenderSlotState>
local State = {}

local function ensure_slot(slot)
  assert(SLOT_SIDE[slot], "md-render: unknown slot " .. tostring(slot))
  if not State[slot] then
    State[slot] = {
      float_win = require("md-render").FloatWin.new("md_render_slot_" .. slot),
      source_bufnr = nil,
    }
  end
  return State[slot]
end

-- Width policy (panels, not content):
--   * Floor / ceiling come from MIN_PANEL_WIDTH / MAX_PANEL_WIDTH at
--     the top of this file. Hard bounds, screen-size independent.
--   * Within those bounds, panels track their content's actual width.
--
-- Column placement still uses the ⅓ grid for predictable left/middle/right
-- positioning. Three MAX_PANEL_WIDTH-wide panels overlap on screens narrower
-- than ~3 × MAX_PANEL_WIDTH; intentional per user spec ("a little overlap
-- is okay since we have focus features").
--
-- Returns (row, col, width, height).
local function geometry(side, content_lines, content_max_width)
  local cols, lines = vim.o.columns, vim.o.lines
  local margin = 1
  local each_outer = math.floor((cols - 4 * margin) / 3) -- ⅓ slot incl. borders
  local width = math.max(MIN_PANEL_WIDTH, math.min(MAX_PANEL_WIDTH, content_max_width + 2))
  local height = math.min(content_lines, math.floor(lines * 0.85))
  local row = 1
  local col
  if side == "left" then
    col = margin
  elseif side == "middle" then
    col = margin + each_outer + margin
  else
    col = margin + 2 * (each_outer + margin)
  end
  -- Keep the float on screen on narrow terminals: if the right edge would
  -- fall off the visible area, slide the float left so it fits flush
  -- against the right margin. Mirrors the plugin's own clamp in
  -- display_utils.open_float_window. On wide screens (each slot's ⅓
  -- position already leaves room for `width`) this is a no-op.
  col = math.min(col, math.max(0, cols - width))
  return row, col, width, height
end

local function is_markdown(bufnr)
  if vim.bo[bufnr].filetype == "markdown" then return true end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name:match("%.md$") ~= nil or name:match("%.markdown$") ~= nil
end

-- Open a slot float displaying `source_bufnr`. Caller is responsible for
-- closing any existing float in this slot first (the toggle entry points
-- below handle that). Mirrors `MdPreview.show()` but with our geometry
-- and persistent (`auto_close = false`) FloatWin.
local function open_slot(slot, source_bufnr)
  local s = ensure_slot(slot)
  if not is_markdown(source_bufnr) then
    vim.notify("md-render: buffer is not markdown", vim.log.levels.WARN)
    return
  end

  local md = require("md-render")
  md.setup_highlights()

  local source_lines = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  local source_name = vim.api.nvim_buf_get_name(source_bufnr)
  local opts = {
    buf_dir = vim.fn.fnamemodify(source_name, ":h"),
    max_width = CONTENT_INTERIOR_WIDTH,
  }
  local fold_state, expand_state = {}, {}

  local content
  local function build()
    opts.fold_state = fold_state
    opts.expand_state = expand_state
    content = md.preview.build_content(source_lines, opts)
    return content
  end
  build()

  local buf = vim.api.nvim_create_buf(false, true)
  local ns = vim.api.nvim_create_namespace("md_render_slot_" .. slot)
  md.display_utils.apply_content_to_buffer(buf, ns, content)

  local content_max_width = 0
  for _, line in ipairs(content.lines) do
    content_max_width = math.max(content_max_width, vim.api.nvim_strwidth(line))
  end
  local row, col, width, height = geometry(SLOT_SIDE[slot], #content.lines, content_max_width)

  local title = (" %s — slot %s "):format(vim.fn.fnamemodify(source_name, ":t"), slot)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  vim.wo[win].wrap = true
  vim.wo[win].cursorline = true
  vim.wo[win].statusline = " "
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- auto_close = false so the float persists across WinEnter/CursorMoved.
  -- Required for slots to coexist while the user moves between sources.
  s.float_win:setup(win, { auto_close = false })
  s.source_bufnr = source_bufnr

  for _, fold in ipairs(content.callout_folds) do
    fold_state[fold.source_line] = fold.collapsed
  end

  local image_state
  image_state = md.display_utils.setup_images(win, content, ns, {
    buf = buf,
    build_content = build,
  })

  -- Re-render after a fold/expand toggle. Keeps existing window layout;
  -- only the buffer contents are replaced.
  local function rebuild()
    build()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    md.display_utils.apply_content_to_buffer(buf, ns, content)
    vim.bo[buf].modifiable = false
    local any_expanded = false
    for _, v in pairs(expand_state) do
      if v then
        any_expanded = true
        break
      end
    end
    vim.wo[win].wrap = not any_expanded
  end

  md.display_utils.setup_float_keymaps(buf, ns, win, content, s.float_win, {
    get_content = function() return content end,
    on_fold_toggle = function(source_line, collapsed)
      fold_state[source_line] = collapsed
      rebuild()
      image_state = md.display_utils.update_images(image_state, win, content)
    end,
    on_expand_toggle = function(block_id, expanded)
      expand_state[block_id] = expanded
      rebuild()
      image_state = md.display_utils.update_images(image_state, win, content)
    end,
  })
end

--- Render the current buffer into `slot`. If the slot already has an open
--- float, it is replaced (the float window closes and a new one opens with
--- the current buffer's content). Notifies if the current buffer isn't
--- markdown — see `open_slot`.
---@param slot "a"|"s"|"d"
function M.render_current(slot)
  local s = ensure_slot(slot)
  s.float_win:close_if_valid()
  open_slot(slot, vim.api.nvim_get_current_buf())
end

--- Render a markdown file at `path` into `slot`, without making it the
--- current buffer. The file is loaded into a hidden buffer (created via
--- `bufadd` + `bufload`) and passed to `open_slot` so its content +
--- relative-path resolution work normally; the user's cursor / window
--- focus are unaffected.
---
--- Intended entry point for external tooling (e.g. the `/document-it
--- show <slot>` skill mode) that wants to push a path into a slot via
--- nvim's RPC socket — call site looks like:
---
---   nvim --server "$NVIM" --remote-send \
---     ":lua require('utils.md_render').render_path('a', [[<path>]])<CR>"
---@param slot "a"|"s"|"d"
---@param path string absolute or `~`-prefixed path to a markdown file
function M.render_path(slot, path)
  local resolved = vim.fn.expand(path)
  if vim.fn.filereadable(resolved) ~= 1 then
    vim.notify("md-render: file not readable: " .. resolved, vim.log.levels.WARN)
    return
  end
  local s = ensure_slot(slot)
  s.float_win:close_if_valid()
  -- bufadd + bufload: creates the buffer if absent, reuses if already
  -- loaded (cheap), populates lines without making the buffer current.
  local bufnr = vim.fn.bufadd(resolved)
  vim.fn.bufload(bufnr)
  open_slot(slot, bufnr)
end

--- Focus slot `slot`. Three-way behavior:
---   1. Float currently open  → jump the cursor into it.
---   2. Float closed but slot has a remembered source → reopen with it
---      (so the same key doubles as "bring it back").
---   3. Slot never rendered yet → fall back to rendering the current
---      buffer. Lets the lowercase key be the smart, frequent action
---      without making the user remember to use uppercase the first time.
---@param slot "a"|"s"|"d"
function M.focus(slot)
  local s = ensure_slot(slot)
  local win = s.float_win.win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end
  -- open_slot uses enter = true, so the cursor lands in the float.
  if s.source_bufnr and vim.api.nvim_buf_is_valid(s.source_bufnr) then
    open_slot(slot, s.source_bufnr)
    return
  end
  open_slot(slot, vim.api.nvim_get_current_buf())
end

return M
