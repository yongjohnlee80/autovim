return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal = {
        split_side = "right",
        split_width_percentage = 0.30,
      },
      -- We manage focus entirely in the autocmd below: keystrokes are
      -- routed into a hidden scratch sink for 500ms so stray keys
      -- (especially <Enter>) can't hit a diff-panel action, then focus
      -- lands on the Claude terminal.
      diff_opts = {
        keep_terminal_focus = false,
      },
    },
    config = function(_, opts)
      require("claudecode").setup(opts)

      local group = vim.api.nvim_create_augroup("claudecode-diff-notify", { clear = true })

      -- Open a 1x1 fully-transparent floating window on a nomodifiable
      -- scratch buffer, take focus there, and close it after `ms` ms.
      -- While focused there, normal-mode keystrokes are inert:
      --   <Enter>, j/k/h/l → no-op on an empty buffer
      --   i / a / o        → "Cannot make changes, 'modifiable' off"
      --   <leader>aa/ad    → still work (global mappings)
      -- After the timer, focus shifts to the Claude terminal.
      local function sink_keystrokes_for(ms)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].modifiable = false

        local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
          relative = "editor",
          row = 0,
          col = 0,
          width = 1,
          height = 1,
          style = "minimal",
          focusable = true,
          noautocmd = true,
          zindex = 250,
        })
        if not ok then return end
        pcall(vim.api.nvim_set_option_value, "winblend", 100, { win = win })

        vim.defer_fn(function()
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
          end
          pcall(vim.cmd, "ClaudeCodeFocus")
        end, ms)
      end

      vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        callback = function(ev)
          -- 30ms lets the plugin finish setting b.claudecode_diff_tab_name
          -- before we check for it (it's set right after BufWinEnter fires).
          vim.defer_fn(function()
            if not vim.api.nvim_buf_is_valid(ev.buf) or not vim.b[ev.buf].claudecode_diff_tab_name then
              return
            end
            vim.notify(
              "Claude diff ready — <leader>aa accept, <leader>ad deny",
              vim.log.levels.WARN,
              { title = "Claude Code" }
            )
            sink_keystrokes_for(500)
          end, 30)
        end,
      })
    end,
    keys = {
      { "<leader>a",  nil,                              desc = "AI/Claude Code" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>",            desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>",       desc = "Focus Claude" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>",   desc = "Resume Claude" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>",       desc = "Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>",        mode = "v", desc = "Send to Claude" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>",  desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>",    desc = "Deny diff" },
    },
  },
}
