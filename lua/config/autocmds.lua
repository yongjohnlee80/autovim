-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

require("utils.float_focus").install_auto_hide()

-- Persist the current colorscheme whenever it changes so that the next
-- nvim start can hot-reload it (see `plugins/theme.lua`). Fires for
-- picker selection, direct `:colorscheme` calls, and Snacks' cancel-path
-- revert — which is exactly what we want (the final state wins).
--
-- The save is STAMPED with Omarchy's active theme name. On Omarchy the theme
-- is applied by Omarchy itself, which also fires ColorScheme — so without a
-- stamp this cache cannot tell a deliberate user pick from an echo of the
-- system theme, and the user ends up permanently pinned to whatever Omarchy
-- last set. `utils.theme_resolve` compares the stamp against Omarchy's current
-- theme to separate the two. On every other platform the stamp is nil and the
-- cache behaves exactly as it always has.
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ThemeCachePersist", { clear = true }),
  callback = function(ev)
    require("utils.theme_cache").save(ev.match, require("utils.platform").omarchy_theme_name())
  end,
})

-- Drop the persisted pick and re-resolve, which lands back on the platform
-- default: Omarchy's system theme, or `catppuccin-mocha` elsewhere. Without
-- this there is no way back to "follow the system" once you have chosen a
-- theme, because any pick you make is by definition an override.
vim.api.nvim_create_user_command("AutovimThemeFollowSystem", function()
  require("utils.theme_cache").clear()
  -- `ignore_cache` asks the resolver what it would pick with no override at
  -- all — the same code path startup uses, so this can never disagree with it.
  local name = require("utils.theme_resolve").current({ ignore_cache = true })
  -- Re-applying fires ColorScheme, which re-saves — but now the saved name and
  -- the stamp agree with the system, so it reads as "following", not override.
  pcall(vim.cmd.colorscheme, name)
  vim.notify("AutoVim theme now follows the system default: " .. name)
end, { desc = "Forget the AutoVim theme override and follow the platform default" })

-- Initial `:colorscheme` applied during LazyVim setup renders with the wrong
-- background material under Ghostty's transparency/blur — it looks like bare
-- system vibrancy instead of the theme's bg. Re-applying the same colorscheme
-- after startup (what the picker does on selection) forces a full repaint that
-- renders correctly. So on VimEnter, artificially re-fire the cached theme.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("ThemeRepaintOnEnter", { clear = true }),
  callback = function()
    local name = vim.g.colors_name
    if name and name ~= "" then
      pcall(vim.cmd.colorscheme, name)
    end
  end,
})

-- Markdown: disable conceal so GFM tables stay visually aligned.
-- LazyVim sets conceallevel=2 globally, and treesitter's markdown_inline
-- query conceals inline markup (** ` * _ ~~). Formatters (prettier) align
-- the RAW source — counting those markers — but conceal hides them at
-- display time, so any cell with bold/code/italic renders narrower than the
-- source and the column pipes stop lining up. nvim can't replace the markers
-- with equal-width spaces (it collapses each multi-char delimiter like ** or
-- ~~ to a single conceal char), so short of a render plugin the clean fix is
-- to turn conceal off for markdown. conceallevel is window-local, so set it
-- per-window on the markdown FileType.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("UserMarkdownConceal", { clear = true }),
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})

-- ── Omarchy: follow the system theme live (requirements 3 + 5) ────────────
--
-- Omarchy switches the whole desktop's theme by re-pointing
-- `~/.config/omarchy/current/theme` and poking running clients; in Neovim that
-- surfaces as `User LazyReload`. Re-resolving here lets an already-open editor
-- track the desktop with no restart.
--
-- Wired in config, NOT as a spec in `lua/plugins/`. The old `omarchy` branch
-- shipped this as a pseudo-plugin with `dir = vim.fn.stdpath("config")`, which
-- `theme-picker.lua` already claims — and lazy dedupes local plugins by `dir`,
-- keeping only the first. So the hot-reload was registered=false and NEVER RAN
-- on that branch. Moving it here is what makes the feature actually work.
--
-- Also simpler than the branch version, which read the theme name out of
-- `plugins.theme`'s spec table and had to unload `package.loaded["plugins.theme"]`
-- to re-read it. `utils.theme_resolve` reads Omarchy's fragment fresh from disk
-- on every call, so there is no cached module state to invalidate — and
-- honouring an AutoVim override is the resolver's job, not this file's.
if require("utils.platform").is_omarchy() then
local transparency = vim.fn.stdpath("config") .. "/plugin/after/transparency.lua"

-- catppuccin and friends compile highlight tables at require time, so a
-- re-apply of the same plugin with different flavour settings can serve
-- stale colours. Dropping the plugin's modules forces a real rebuild.
local function unload_colorscheme_plugin(name)
  local ok, config = pcall(require, "lazy.core.config")
  if not ok then
    return
  end
  for _, plugin in pairs(config.plugins or {}) do
    local declares = plugin.name == name
      or (plugin[1] and tostring(plugin[1]):find(name, 1, true) ~= nil)
    if declares and plugin.dir then
      pcall(function()
        require("lazy.core.util").walkmods(plugin.dir .. "/lua", function(modname)
          package.loaded[modname] = nil
          package.preload[modname] = nil
        end)
      end)
    end
  end
end

vim.api.nvim_create_autocmd("User", {
  pattern = "LazyReload",
  group = vim.api.nvim_create_augroup("OmarchyThemeHotreload", { clear = true }),
  callback = function()
    vim.schedule(function()
      -- Reads Omarchy's fragment from disk, so this is the NEW theme.
      local name = require("utils.theme_resolve").current()
      if not name or name == "" then
        return
      end

      -- Base name of the plugin behind e.g. `catppuccin-mocha`.
      unload_colorscheme_plugin((name:gsub("%-.*$", "")))

      vim.cmd("highlight clear")
      if vim.fn.exists("syntax_on") == 1 then
        vim.cmd("syntax reset")
      end
      -- Let the colorscheme choose; a light theme sets this itself.
      vim.o.background = "dark"

      -- The new theme's plugin may never have been loaded. Ask lazy to
      -- bring it in before applying, or `:colorscheme` fails outright.
      pcall(function()
        require("lazy.core.loader").colorscheme(name)
      end)

      -- `vim.cmd.colorscheme` fires ColorScheme natively, which is what
      -- theme-aware consumers listen to (the splash header re-paints on
      -- it, and `ThemeCachePersist` re-stamps the cache). Do NOT re-fire
      -- VimEnter here: that re-runs every registered VimEnter autocmd on
      -- a live session and clobbers open panels and terminals.
      if not pcall(vim.cmd.colorscheme, name) then
        vim.notify(
          ("Omarchy theme '%s' could not be applied"):format(name),
          vim.log.levels.WARN
        )
        return
      end

      if vim.fn.filereadable(transparency) == 1 then
        pcall(vim.cmd.source, transparency)
      end
      vim.cmd("redraw!")
    end)
  end,
})
end
