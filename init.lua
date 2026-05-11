-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- User-owned custom override layer (NvChad-style). Loaded LAST so it
-- can re-set vim.opt.*, override / add keymaps, register extra
-- autocmds, and require sibling files under `lua/custom/`. Plugin
-- specs are picked up by lazy.nvim itself via the conditional
-- `{ import = "custom.plugins" }` in `lua/config/lazy.lua`.
--
-- Missing `lua/custom/init.lua` is fine — pcall swallows the require
-- error. See `docs/custom-example/` for the starter templates the
-- installer copies into `lua/custom/` on fresh install.
pcall(require, "custom")
