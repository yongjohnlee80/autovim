-- <leader> which-key trigger guard (ADR-0091)
--
-- Installs a NET over which-key that detects and repairs silent loss of the
-- buffer-local `<leader>` popup trigger — in the same process, without a
-- restart. which-key itself stays exactly as LazyVim configures it: same
-- opts, same pin, no fork. See `lua/utils/leader_guard.lua` for the guard and
-- `lua/utils/wk_compat.lua` for the single narrow internals seam.
--
-- Turn off with an override in lua/custom/plugins/:
--   return { { "folke/which-key.nvim", init = function() vim.g.autovim_leader_guard = false end } }
-- or :let g:autovim_leader_guard = 0 at runtime (takes effect on the next event).

return {
  "folke/which-key.nvim",
  init = function()
    require("utils.leader_guard").setup()
  end,
}
