-- AutoVim user-custom entrypoint.
--
-- Sourced by `init.lua` (the AutoVim root) via `pcall(require, "custom")`
-- AFTER `config.lazy` has set up LazyVim + stock plugins. By the time
-- this file runs:
--   * stock options / keymaps / autocmds have applied
--   * stock plugin specs have been resolved
--   * lua/custom/plugins/* specs (if any) have merged on top
--
-- This is the right place to:
--   * re-set vim.opt.* values (`require("custom.options")`)
--   * override / add keymaps  (`require("custom.keymaps")`)
--   * install user autocmds   (`require("custom.autocmds")`)
--   * one-off init that doesn't belong in a plugin spec
--
-- Each `require` is wrapped in `pcall` so a stray syntax error in one
-- file doesn't take the whole config down — fix the error, restart nvim.

pcall(require, "custom.options")
pcall(require, "custom.keymaps")
pcall(require, "custom.autocmds")
