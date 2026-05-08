-- Minimal neo-tree override. Auto-finder owns the panel width and pushes it
-- into neo-tree's `window.width` on mount/resize, so we don't set width here.
-- We only customize what auto-finder doesn't touch: filesystem visibility and
-- the dotfile name highlight. We also disable the netrw hijack so that
-- `nvim .` doesn't autostart a standalone neo-tree window — auto-finder is
-- the entry point now, and the autostart would otherwise leave the cursor
-- inside a neo-tree buffer when <leader>e fires (the new panel would then
-- inherit the neo-tree filetype, and neo-tree's command override would
-- redirect our `position = "current"` mount back to the autostart window).
return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    -- Auto-finder is the user-facing entry point for the file explorer
    -- now. Drop LazyVim's default neo-tree keymaps (<leader>fe / fE /
    -- ge / be / e / E) so we don't end up with two competing
    -- explorers. neo-tree stays loaded as auto-finder's filesystem
    -- backend; its `:Neotree` user command also gets shadowed below
    -- so users don't accidentally summon a separate window.
    keys = function()
      return {}
    end,
    cmd = nil,  -- drop LazyVim's `cmd = "Neotree"` lazy-trigger
    opts = {
      window = {
        -- Let neo-tree expand the panel beyond auto-finder's
        -- configured width when a filename is longer than the panel
        -- can hold. Won't shrink — the panel still respects
        -- auto-finder's min/max — but it stops the case where a long
        -- filename gets truncated mid-word with no recourse.
        auto_expand_width = true,
      },
      filesystem = {
        hijack_netrw_behavior = "disabled",
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
        },
        check_gitignore_in_search = false,
        components = {
          name = function(config, node, state)
            local cc = require("neo-tree.sources.common.components")
            local result = cc.name(config, node, state)
            local name = node.name or ""
            if node.type ~= "directory" and name:sub(1, 1) == "." then
              result.highlight = "NeoTreeDotfile"
            end
            return result
          end,
        },
      },
    },
  },
}
