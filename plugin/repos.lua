local function add(opts)
  require("utils.repos").add(opts.args ~= "" and opts.args or nil)
end

vim.api.nvim_create_user_command("RepoRegister", add, {
  nargs = "?",
  complete = "dir",
  desc = "Register a repo for the <leader>e tree (defaults to cwd)",
})

vim.api.nvim_create_user_command("RepoAdd", add, {
  nargs = "?",
  complete = "dir",
  desc = "Alias of :RepoRegister",
})

vim.api.nvim_create_user_command("RepoUnregister", function(opts)
  require("utils.repos").remove(opts.args)
end, { nargs = 1, complete = "dir", desc = "Unregister a repo" })

vim.api.nvim_create_user_command("RepoRemove", function(opts)
  require("utils.repos").remove(opts.args)
end, { nargs = 1, complete = "dir", desc = "Alias of :RepoUnregister" })

vim.api.nvim_create_user_command("RepoList", function()
  local repos = require("utils.repos").load()
  if #repos == 0 then
    print("(no registered repos)")
    return
  end
  for _, p in ipairs(repos) do print(p) end
end, { desc = "List registered repos" })

vim.api.nvim_create_user_command("RepoSync", function()
  require("utils.repos").sync()
  vim.notify("repos: registry synced (" .. require("utils.repos").registry_dir() .. ")")
end, { desc = "Rebuild the repo-tree symlink registry" })
