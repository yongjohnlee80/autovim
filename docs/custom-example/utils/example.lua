-- Example user helper.
--
-- Save your own utilities under `lua/custom/utils/<name>.lua` and call
-- them from anywhere via `require("custom.utils.<name>")`. The custom
-- tree is on the runtime path because the AutoVim repo IS your config
-- dir (`stdpath("config") .. "/lua/custom/utils/"` resolves naturally).

local M = {}

---Example: scratch-buffer toggle.
function M.scratch()
  vim.cmd("new")
  vim.bo.buftype  = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.swapfile = false
end

return M
