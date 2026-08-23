-- gopls: tag-neutral everywhere, and Mason-free on macOS.
--
-- ── Build tags (all platforms) ────────────────────────────────────────────
-- Go files behind a build constraint (`//go:build <tag>`) are invisible to
-- gopls unless that tag is active: gopls logs "no package metadata for file"
-- and InlayHint / references / diagnostics silently fail in them. The fix is
-- `settings.gopls.buildFlags = { "-tags=<a,b,c>" }`.
--
-- Build tags are per-developer / per-repo (one monorepo wants
-- `test,gold,integration`, another wants something else), so this SHARED spec
-- deliberately sets none — baking one project's tags into everyone's config is
-- the wrong default. Add the tags YOUR codebase needs in the gitignored custom
-- layer at `lua/custom/plugins/gopls.lua`:
--
--     return {
--       {
--         "neovim/nvim-lspconfig",
--         opts = function(_, opts)
--           local servers = opts.servers or {}
--           opts.servers = servers
--           servers.gopls = servers.gopls or {}
--           servers.gopls.settings = servers.gopls.settings or {}
--           servers.gopls.settings.gopls = servers.gopls.settings.gopls or {}
--           servers.gopls.settings.gopls.buildFlags = { "-tags=integration,gold" }
--         end,
--       },
--     }
--
-- FUNCTION form on purpose: lazy.nvim CONCATENATES list-valued `opts` across
-- spec fragments, so a table `buildFlags = {...}` in a second fragment would
-- append a duplicate `-tags=` flag instead of replacing. worktree.nvim restarts
-- gopls on worktree-switch, so the override re-applies automatically.
--
-- (The `/go-test-env` skill can scaffold this file for you — pick the `lsp`
-- target.)
--
-- ── Keeping gopls outside Mason (macOS only) ──────────────────────────────
-- Mason occasionally lags Go's module/proxy state for new gopls releases, which
-- can make first-run installs fail even when `go install ...` works. On macOS
-- AutoVim treats gopls as a system Go tool and lets Mason continue managing the
-- rest of the Go toolchain helpers (goimports, gofumpt, delve, etc.).
--
-- This is deliberately NOT applied on Linux, where Mason-managed gopls is the
-- intended install boundary and works. The override used to live on the
-- `mac-os` git branch; it is gated at runtime here so a single `main` serves
-- both platforms.

local platform = require("utils.platform")

if not platform.is_macos() then
  return {}
end

local mason_bin = vim.fs.normalize(vim.fn.stdpath("data") .. "/mason/bin")

local function system_path_entries()
  local entries = {}
  for _, dir in ipairs(vim.fn.split(vim.env.PATH or "", ":")) do
    if dir ~= "" and vim.fs.normalize(dir) ~= mason_bin then
      entries[#entries + 1] = dir
    end
  end
  return entries
end

local function system_path()
  return table.concat(system_path_entries(), ":")
end

local function system_gopls_path()
  for _, dir in ipairs(system_path_entries()) do
    local candidate = dir .. "/gopls"
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
end

local function notify_missing_gopls()
  if vim.fn.executable("go") == 0 or system_gopls_path() then
    return
  end

  vim.schedule(function()
    vim.notify(
      "AutoVim: gopls is not on PATH. Install it with:\n" .. "go install golang.org/x/tools/gopls@latest",
      vim.log.levels.WARN,
      { title = "AutoVim Go LSP" }
    )
  end)
end

return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.api.nvim_create_autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("autovim_gopls_health", { clear = true }),
        callback = notify_missing_gopls,
      })
    end,
    opts = {
      servers = {
        gopls = {
          mason = false,
          cmd = { system_gopls_path() or "gopls" },
          cmd_env = {
            PATH = system_path(),
          },
        },
      },
    },
  },
}
