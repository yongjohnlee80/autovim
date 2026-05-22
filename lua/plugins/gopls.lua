-- Keep gopls outside Mason.
--
-- mac-os branch only: do not merge this override into main/Linux branches
-- unless those branches also intentionally make `gopls` a system dependency.
-- Linux packages can keep relying on Mason-managed gopls if that is the desired
-- install boundary there.
--
-- Mason occasionally lags Go's module/proxy state for new gopls releases, which
-- can make first-run installs fail even when `go install ...` works. AutoVim
-- treats gopls as a system Go tool and lets Mason continue managing the rest of
-- the Go toolchain helpers (goimports, gofumpt, delve, etc.).
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
