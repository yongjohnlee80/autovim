-- Leader recovery — keep `<leader>` opening which-key without a restart (ADR-0091)
--
-- which-key installs its leader trigger as a BUFFER-LOCAL native mapping. When
-- that mapping is lost, `<leader>x` is only a PREFIX of the real mappings and
-- none of them complete — so Vim waits `timeoutlen`, finds no match, and
-- REPLAYS THE KEYS LITERALLY. `<leader>a` moves the cursor right and enters
-- insert; `<leader>m` sets a mark; `<leader>w` writes the file. Nothing errors,
-- and every letter fails differently, so it does not look like one bug.
--
-- Restarting Neovim is not an acceptable recovery here: this editor hosts
-- long-running agent terminals, and a session may hold the only live handle on
-- hours of work.
--
-- This spec is ADDITIVE. It does not redeclare which-key, override its opts,
-- pin a fork, or touch LazyVim's resolved configuration — it attaches after
-- which-key has loaded and asks it to re-attach when its own trigger is gone.
--
-- Deleting this feature is one commit: this file, lua/utils/leader_recovery.lua,
-- lua/utils/wk_adapter.lua, tests/leader-recovery.lua.
return {
  {
    "folke/which-key.nvim",
    -- `optional` so this NEVER declares which-key. LazyVim owns the spec; if it
    -- ever stops shipping which-key, this entry evaporates instead of resurrecting
    -- the plugin behind the distro's back.
    optional = true,
    -- `init` + `on_load`, deliberately NOT `config` or `opts`: overriding either
    -- would replace or reshape LazyVim's resolved which-key configuration, and
    -- the requirement is to inherit it untouched. This only appends a listener
    -- that runs after which-key has loaded itself, however it was configured.
    init = function()
      local function attach()
        require("utils.leader_recovery").setup()
      end
      local ok, LazyVimUtil = pcall(require, "lazyvim.util")
      if ok and type(LazyVimUtil.on_load) == "function" then
        LazyVimUtil.on_load("which-key.nvim", attach)
      else
        -- Fallback for a LazyVim without on_load: wait for the plugin to load.
        vim.api.nvim_create_autocmd("User", {
          pattern = "LazyLoad",
          callback = function(ev)
            if ev.data == "which-key.nvim" then attach() end
          end,
        })
      end
    end,
  },
}
