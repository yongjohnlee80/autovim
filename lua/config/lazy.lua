local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- User-owned plugin overrides (NvChad-style). When the user has
-- placed any spec files under `lua/custom/plugins/`, lazy.nvim
-- imports them AFTER the stock specs above, so its by-name spec
-- merging applies: a user spec sharing the repo name of a stock
-- one merges its `opts` / `keys` / `enabled` / `dependencies` on
-- top. New plugins added by the user just slot in.
--
-- The `lua/custom/` tree is gitignored (see `.gitignore`); the
-- installer scaffolds it from `docs/custom-example/` on fresh
-- install. `update.sh` / `git pull` never touches it because git
-- doesn't track that subtree.
local _config_dir = vim.fn.stdpath("config")
local _has_custom_plugins =
  vim.fn.isdirectory(_config_dir .. "/lua/custom/plugins") == 1

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
    -- user-owned overrides (optional; absent until user opts in)
    _has_custom_plugins and { import = "custom.plugins" } or nil,
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
