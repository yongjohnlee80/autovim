-- gopls build-tag awareness.
--
-- Files with `//go:build test` (e.g. pkg/**/*_test.go in the LabelManager
-- monorepo) and `//go:build gold` (e.g. gold-only test files) are invisible
-- to gopls unless the matching tag is active. Without this, gopls logs
-- "no package metadata for file" for those files and InlayHint / refs /
-- diagnostics silently fail.
--
-- LazyVim's lang.go extra already sets up gopls; this spec just merges in
-- the extra buildFlags on top. Re-applies automatically on worktree-switch
-- because worktree.nvim restarts gopls via lsp_servers_to_restart.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          settings = {
            gopls = {
              buildFlags = { "-tags=test,gold" },
            },
          },
        },
      },
    },
  },
}
