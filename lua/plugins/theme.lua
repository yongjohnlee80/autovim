-- LazyVim's `opts.colorscheme` used to hard-code a single theme, which meant
-- every nvim restart wiped whatever the user had picked via <leader>ut.
--
-- Function form reads `utils.theme_cache` (populated by the ColorScheme
-- autocmd in `config/autocmds.lua` on every `:colorscheme` call) and applies
-- that. On a fresh install with no cache yet, we fall back to `system` —
-- the transparent pseudo-theme in `colors/system.lua` — so the distribution
-- default shows off the user's terminal theme rather than imposing one.

return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local cached = require("utils.theme_cache").load()
        local name = cached or "system"
        local ok, err = pcall(vim.cmd.colorscheme, name)
        if not ok then
          vim.notify(
            ("theme '%s' failed to load (%s), falling back to `system`"):format(name, err),
            vim.log.levels.WARN
          )
          pcall(vim.cmd.colorscheme, "system")
        end
      end,
    },
  },
}
