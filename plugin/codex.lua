local codex = require("utils.codex")
local term_send = require("utils.term_send")

vim.api.nvim_create_user_command("Codex", function(opts)
  term_send.toggle_codex({ force_new = opts.bang })
end, {
  bang = true,
  desc = "Toggle Codex in slot 5 (! starts a new session)",
})

vim.api.nvim_create_user_command("CodexSafe", function(opts)
  term_send.toggle_codex({ mode = "safe", force_new = opts.bang })
end, {
  bang = true,
  desc = "Open safe-mode Codex in slot 5, replacing any trusted session (! starts fresh)",
})

vim.api.nvim_create_user_command("CodexTrusted", function(opts)
  term_send.toggle_codex({ mode = "trusted", force_new = opts.bang })
end, {
  bang = true,
  desc = "Open trusted-mode Codex in slot 5, replacing any safe session (! starts fresh)",
})

vim.api.nvim_create_user_command("CodexExec", function(opts)
  codex.exec(opts.args, { workspace_write = opts.bang })
end, {
  bang = true,
  nargs = "*",
  desc = "Run Codex exec in the current project (! allows workspace writes)",
})

vim.api.nvim_create_user_command("CodexSendFile", function(opts)
  codex.send_file(opts.args, { workspace_write = opts.bang })
end, {
  bang = true,
  nargs = "*",
  desc = "Send the current buffer to Codex (! allows workspace writes)",
})

vim.api.nvim_create_user_command("CodexSendSelection", function(opts)
  codex.send_selection(opts.args, {
    workspace_write = opts.bang,
    range = opts.range > 0 and { line1 = opts.line1, line2 = opts.line2 } or nil,
  })
end, {
  bang = true,
  nargs = "*",
  range = true,
  desc = "Send the current visual selection to Codex (! allows workspace writes)",
})

vim.api.nvim_create_user_command("CodexPatch", function(opts)
  codex.patch(opts.args)
end, {
  nargs = "*",
  desc = "Ask Codex for an editable project patch",
})

vim.api.nvim_create_user_command("CodexPatchFile", function(opts)
  codex.patch_file(opts.args)
end, {
  nargs = "*",
  desc = "Ask Codex for an editable patch for the current file",
})

vim.api.nvim_create_user_command("CodexPatchSelection", function(opts)
  codex.patch_selection(opts.args, {
    range = opts.range > 0 and { line1 = opts.line1, line2 = opts.line2 } or nil,
  })
end, {
  nargs = "*",
  range = true,
  desc = "Ask Codex for an editable patch for the current selection",
})

vim.api.nvim_create_user_command("CodexDiffAccept", function()
  codex.accept_patch()
end, {
  desc = "Accept the current Codex patch buffer",
})

vim.api.nvim_create_user_command("CodexDiffDeny", function()
  codex.deny_patch()
end, {
  desc = "Discard the current Codex patch buffer",
})

vim.api.nvim_create_user_command("CodexDiffRefresh", function()
  codex.refresh_patch_preview()
end, {
  desc = "Refresh the current Codex patch preview",
})

vim.keymap.set("n", "<leader>A", "<Nop>", { desc = "AI/Codex" })
vim.keymap.set("n", "<leader>Ac", "<cmd>Codex<cr>", { desc = "Codex Resume" })
vim.keymap.set("n", "<leader>AN", "<cmd>Codex!<cr>", { desc = "Codex New Session" })
vim.keymap.set("n", "<leader>As", "<cmd>CodexSafe<cr>", { desc = "Codex (safe)" })
vim.keymap.set("n", "<leader>At", "<cmd>CodexTrusted<cr>", { desc = "Codex (trusted)" })
vim.keymap.set("n", "<leader>Ae", function()
  codex.exec()
end, { desc = "Codex Exec" })
vim.keymap.set("n", "<leader>Af", function()
  codex.send_file()
end, { desc = "Codex Send File" })
vim.keymap.set("n", "<leader>Ap", function()
  codex.patch_file()
end, { desc = "Codex Patch File" })
vim.keymap.set("n", "<leader>AP", function()
  codex.patch()
end, { desc = "Codex Patch Project" })
vim.keymap.set("n", "<leader>Ar", function()
  codex.refresh_patch_preview()
end, { desc = "Codex Refresh Patch Preview" })
vim.keymap.set("x", "<leader>As", function()
  codex.send_selection()
end, { desc = "Codex Send Selection" })
vim.keymap.set("x", "<leader>Ap", function()
  codex.patch_selection()
end, { desc = "Codex Patch Selection" })
