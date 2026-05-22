-- snacks.picker `jump` action — guard against `winfixbuf` targets.
--
-- snacks.picker (`actions.lua:139`) runs `vim.cmd("buffer <bufnr>")` in the
-- currently focused window after closing the picker float. When that window
-- has `winfixbuf=true` (auto-core panel, or any window deliberately marked
-- `winfixbuf` by another plugin — e.g. gitsigns blame, nvim-dap-view
-- splits), the buffer load raises `E1513: Cannot switch buffer. 'winfixbuf'
-- is enabled`. The original hypothesis that `:split` / `:vsplit` propagates
-- `winfixbuf=true` from the panel to a new window was NOT confirmed on
-- nvim 0.12.2 (see Lector audit reply 2026-05-23 in
-- `shared/synthesis/auto-core-winfixbuf-guard-justification-review.md`);
-- this wrap is cause-agnostic and covers the snacks E1513 vector regardless
-- of how the focused window came to be `winfixbuf=true`.
--
-- Mirrors the same pattern `lua/plugins/bufferline.lua`'s
-- `safe_buffer_click` uses for bufferline tab clicks — including the
-- all-windows-fixed fallback (open a fresh editor split when no non-fixed
-- sibling exists).
--
-- ADR: shared/adrs/0027-winfixbuf-propagation-defensive-guard.md (Fix A).
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.picker = opts.picker or {}

      -- Move focus off a `winfixbuf` window to a sibling that accepts
      -- `:buffer`. Iterate in reverse so we tend to land on the
      -- rightmost main editor window when both auto-finder (left) and
      -- an agent panel (right) are open. If every non-floating sibling
      -- is also `winfixbuf=true`, open a fresh editor split — without
      -- this fallback the picker would still fire `:buffer` in the
      -- panel and raise E1513.
      local function retarget_non_winfixbuf()
        local cur = vim.api.nvim_get_current_win()
        local cur_fixed = false
        pcall(function() cur_fixed = vim.wo[cur].winfixbuf end)
        if not cur_fixed then return end

        local wins = vim.api.nvim_list_wins()
        for i = #wins, 1, -1 do
          local w = wins[i]
          if w ~= cur then
            local cfg_ok, cfg = pcall(vim.api.nvim_win_get_config, w)
            if cfg_ok and cfg.relative == "" then
              local ok, wfb = pcall(function() return vim.wo[w].winfixbuf end)
              if ok and not wfb then
                pcall(vim.api.nvim_set_current_win, w)
                return
              end
            end
          end
        end

        -- No suitable sibling — split a new editor window. `aboveleft
        -- new` opens a horizontal split with a fresh empty buffer
        -- above; the caller's `:buffer N` then replaces it cleanly
        -- without competing with the panels' `winfixwidth`.
        vim.cmd("aboveleft new")
      end

      local default_jump = require("snacks.picker.actions").jump
      opts.picker.actions = vim.tbl_deep_extend("force", opts.picker.actions or {}, {
        jump = function(picker, item, action)
          retarget_non_winfixbuf()
          return default_jump(picker, item, action)
        end,
      })
    end,
  },
}