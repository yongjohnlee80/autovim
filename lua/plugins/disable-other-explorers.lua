-- Disable competing file-explorers so auto-finder owns the directory-
-- hijack flow on `nvim .` and the `<leader>e` keymap surface.
--
-- 1) Upstream `nvim-neo-tree/neo-tree.nvim` — auto-finder.nvim (v0.1.3+)
--    bundles its own forked copy under
--    `auto-finder.nvim/lua/auto-finder/neotree/`. LazyVim's
--    `lazyvim.plugins.extras.editor.neo-tree` extra was removed from
--    `~/.config/nvim/lazyvim.json`; this belt-and-braces spec makes
--    sure nothing else can pull upstream back in.
--
-- 2) snacks.explorer — LazyVim auto-imports
--    `lazyvim.plugins.extras.editor.snacks_explorer` whenever snacks is
--    installed (install_version=8 makes it the default explorer).
--    snacks.explorer's `setup()` registers a global `BufEnter` autocmd
--    (group "snacks.explorer") that fires `Snacks.explorer({cwd=…})`
--    on the first directory buffer it sees, racing auto-finder's own
--    BufEnter hijack and winning because snacks loads earlier in the
--    plugin spec list. Setting `explorer.enabled = false` makes
--    snacks's loader skip the explorer module entirely (the gate is
--    `M.config[snack].enabled` in snacks/init.lua's `load()`), so the
--    BufEnter handler never gets installed.
--
--    Side benefit: with snacks.explorer disabled, the snacks dashboard
--    stops "skipping" on `nvim .` (its `argc == 1 && isdirectory`
--    skip-bypass at dashboard.lua:1117 only triggers when
--    `explorer.enabled == true`), so it correctly bails on directory
--    args and never paints the AutoVim splash on top of our panel.
return {
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },
  {
    "folke/snacks.nvim",
    opts = {
      explorer = { enabled = false },
    },
  },
}
