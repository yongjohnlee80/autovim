-- snacks.picker `jump` action — guard against `winfixbuf` targets.
--
-- snacks.picker (`actions.lua:139`) runs `vim.cmd("buffer <bufnr>")` in the
-- currently focused window after closing the picker float. When that window
-- has `winfixbuf=true` (auto-core panel, or a regular window that inherited
-- the option from the panel via `:split` propagation), the buffer load raises
-- `E1513: Cannot switch buffer. 'winfixbuf' is enabled`.
--
-- Mirrors the same pattern `lua/plugins/bufferline.lua`'s
-- `safe_buffer_click` uses for bufferline tab clicks. The structural fix for
-- the inheritance class is in auto-core (`fix/winfixbuf-propagation`) — this
-- consumer-side wrap handles the snacks-specific path; both can coexist.
--
-- ADR: shared/adrs/0027-winfixbuf-propagation-defensive-guard.md (Fix A).
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.picker = opts.picker or {}

      local function retarget_non_winfixbuf()
        local cur = vim.api.nvim_get_current_win()
        local cur_fixed = false
        pcall(function() cur_fixed = vim.wo[cur].winfixbuf end)
        if not cur_fixed then return end

        for _, w in ipairs(vim.api.nvim_list_wins()) do
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