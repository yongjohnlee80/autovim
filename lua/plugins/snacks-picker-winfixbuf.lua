-- snacks.picker `jump` action — guard against `winfixbuf` targets.
--
-- snacks.picker (`actions.lua:139`) runs `vim.cmd("buffer <bufnr>")` in the
-- currently focused window after closing the picker float. When that window
-- has `winfixbuf=true` (auto-core panel, or any window deliberately marked
-- `winfixbuf` by another plugin — e.g. gitsigns blame, nvim-dap-view
-- splits), the buffer load raises `E1513: Cannot switch buffer. 'winfixbuf'
-- is enabled`.
--
-- Why a module-level monkey-patch instead of `opts.picker.actions.jump`:
-- many picker sources set `confirm = "jump"` (a string), and snacks
-- resolves that string via `M.action()` which checks
-- `picker.opts.actions["jump"]` first, then falls through to
-- `require("snacks.picker.actions").jump` directly. The `opts.picker.actions`
-- merge path was not reliably propagating to `picker.opts.actions` for the
-- file/smart picker `<leader><leader>` invokes, so the override never fired.
-- Replacing `M.jump` on the actions module table intercepts ALL callers,
-- including the recursive `M.jump(picker, _, action)` call inside the
-- insert-mode reschedule (actions.lua:42) — that line reads `M.jump` from
-- the module table at call time, so it picks up our replacement.
--
-- ADR: shared/adrs/0027-winfixbuf-propagation-defensive-guard.md (Fix A).
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      -- Find a non-floating, non-`winfixbuf` window to use as the
      -- jump target. Iterate in reverse so we tend to land on the
      -- rightmost main editor window when both auto-finder (left) and
      -- an agent panel (right) are open. Returns nil when every
      -- non-floating window is winfixbuf=true.
      local function find_non_winfixbuf_win()
        local wins = vim.api.nvim_list_wins()
        for i = #wins, 1, -1 do
          local w = wins[i]
          local cfg_ok, cfg = pcall(vim.api.nvim_win_get_config, w)
          if cfg_ok and cfg.relative == "" then
            local ok, wfb = pcall(function() return vim.wo[w].winfixbuf end)
            if ok and not wfb then
              return w
            end
          end
        end
        return nil
      end

      -- Ensure `picker.main` points at a window where `:buffer N` will
      -- succeed. snacks' M.jump calls `picker:close()` which restores
      -- focus to `self.main`; if that's a winfixbuf panel the
      -- subsequent `:buffer` raises E1513. picker.main is a property
      -- (snacks/picker/core/picker.lua:43-58) that proxies to
      -- `_main:set()` / `_main:get()`, so assignment propagates.
      local function ensure_picker_main_safe(picker)
        if not (picker and picker.main and vim.api.nvim_win_is_valid(picker.main)) then
          return
        end
        local ok, wfb = pcall(function() return vim.wo[picker.main].winfixbuf end)
        if not (ok and wfb) then return end
        local target = find_non_winfixbuf_win()
        if target then
          picker.main = target
        else
          vim.cmd("aboveleft new")
          picker.main = vim.api.nvim_get_current_win()
        end
      end

      -- Also retarget the CURRENT window if it happens to be winfixbuf
      -- at the time of dispatch. Rare path: action dispatched outside
      -- the picker-input float (some pickers route confirm differently).
      local function retarget_current_if_winfixbuf()
        local cur = vim.api.nvim_get_current_win()
        local ok, wfb = pcall(function() return vim.wo[cur].winfixbuf end)
        if not (ok and wfb) then return end
        local target = find_non_winfixbuf_win()
        if target then
          pcall(vim.api.nvim_set_current_win, target)
        else
          vim.cmd("aboveleft new")
        end
      end

      -- ── Module-level monkey-patch of snacks.picker.actions.jump ──
      --
      -- Replace the function on the actions module table. The recursive
      -- M.jump call at actions.lua:42 reads M.jump at call time, so it
      -- picks up our replacement too — covers the insert-mode
      -- reschedule path that bypasses the opts-based override.
      local snacks_actions = require("snacks.picker.actions")
      local original_jump = snacks_actions.jump
      -- Idempotency guard: don't double-wrap on `:Lazy reload`.
      if not snacks_actions.__wfb_wrapped then
        snacks_actions.__wfb_wrapped = true
        snacks_actions.jump = function(picker, item, action)
          ensure_picker_main_safe(picker)
          retarget_current_if_winfixbuf()
          return original_jump(picker, item, action)
        end
      end

      -- Belt-and-braces: also surface the wrap via opts.picker.actions
      -- in case some sources DO honor that override path.
      opts.picker = opts.picker or {}
      opts.picker.actions = vim.tbl_deep_extend("force", opts.picker.actions or {}, {
        jump = snacks_actions.jump,
      })
    end,
  },
}