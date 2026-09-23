-- Rust editor support (ADR 0194 — Phase 1a).
--
-- AutoVim ships Rust as a first-class TRACKED language by wiring the
-- config-independent toolchain BINARIES — rust-analyzer, rustfmt, clippy, and
-- the rust/ron Treesitter grammars — through the same seams every other AutoVim
-- language uses. It deliberately does NOT import LazyVim's `lang.rust` extra:
-- that extra pulls `rustaceanvim`, a Lua layer that owns the rust-analyzer
-- client OUTSIDE the `opts.servers` idiom, binds `<leader>dr` (auto-run.nvim's
-- debug namespace), and owns its own DAP — the exact config-coupling ADR 0194's
-- task lesson warns against. rust-analyzer is a plain LSP server here, and
-- run/test/debug is owned by auto-run.nvim's `rust` adapter (Phase 1b), keeping
-- one debug/test owner across Go and Rust.
--
-- Unlike `gopls.lua` (a macOS-only override — the base gopls settings come from
-- LazyVim's go extra), there is no `lang.rust` extra, so THIS file owns the
-- whole rust-analyzer config on every platform. The only platform split is
-- acquisition (ADR 0194 §2.6), asserted BOTH directions in tests/smoke.lua:
--
--   • rust-analyzer / rustfmt / clippy belong to `rustup`. On macOS take
--     rust-analyzer from the rustup toolchain (Mason's macOS builds can lag,
--     same reasoning as `gopls.lua`); on Linux let Mason manage it.
--   • codelldb (the DAP adapter auto-run's rust adapter drives) is
--     Mason-managed on ALL platforms — there is no rustup/system codelldb to
--     prefer, and `auto-run.lua` already Mason-installs delve ungated.
--
-- Per-repo tuning (extra `cargo.features`, target dir, etc.) belongs in the
-- gitignored custom layer at `lua/custom/plugins/rust.lua`, merged after this
-- one — same pattern the `gopls.lua` header documents for build tags.

local platform = require("utils.platform")

-- Probe ONCE at load (platform-specific-code-segregation rule 4). tests/smoke.lua
-- re-loads this file under a stubbed `platform.probe.sysname` to assert both
-- gate directions, so the value is re-derived per load — never a hot-path call.
local IS_MACOS = platform.is_macos()

-- rust-analyzer server settings — applied on EVERY platform.
--   • cargo.allFeatures + buildScripts: analyse feature-gated + build-script code
--   • procMacro.enable: expand proc-macros for accurate analysis
--   • check.command = "clippy": clippy diagnostics flow THROUGH rust-analyzer's
--     check-on-save (ADR 0194 OQ5) — no second nvim-lint clippy process.
local RUST_ANALYZER_SETTINGS = {
  ["rust-analyzer"] = {
    cargo = { allFeatures = true, buildScripts = { enable = true } },
    procMacro = { enable = true },
    check = { command = "clippy" },
  },
}

-- ── macOS: rust-analyzer from the system rustup toolchain, not Mason ────────
-- Mirrors gopls.lua: strip Mason's bin dir from the LSP process PATH so the
-- server + the cargo/rustc it spawns resolve to the rustup toolchain.
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

local function system_rust_analyzer_path()
  for _, dir in ipairs(system_path_entries()) do
    local candidate = dir .. "/rust-analyzer"
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
end

return {
  -- LSP: rust-analyzer via the `opts.servers` merge idiom (see gopls.lua).
  -- No `init`/health autocmd here on purpose: gopls.lua already registers one
  -- on nvim-lspconfig (macOS), and lazy.nvim does NOT merge `init` functions
  -- across spec fragments — a second one would silently clobber the first. A
  -- missing rustup toolchain surfaces through lspconfig/Mason on its own.
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local servers = opts.servers or {}
      opts.servers = servers
      servers.rust_analyzer = servers.rust_analyzer or {}
      servers.rust_analyzer.settings = vim.tbl_deep_extend(
        "force",
        servers.rust_analyzer.settings or {},
        RUST_ANALYZER_SETTINGS
      )
      if IS_MACOS then
        -- Take rust-analyzer from rustup, not Mason.
        servers.rust_analyzer.mason = false
        servers.rust_analyzer.cmd = { system_rust_analyzer_path() or "rust-analyzer" }
        servers.rust_analyzer.cmd_env = { PATH = system_path() }
      end
    end,
  },

  -- Treesitter: rust + ron grammars (highlighting + the adapter's discovery).
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "rust", "ron" })
    end,
  },

  -- Formatting: rustfmt via conform (rustup component; documented prerequisite).
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.rust = { "rustfmt" }
    end,
  },

  -- Mason binaries. codelldb on every platform; rust-analyzer on Linux only
  -- (macOS takes it from rustup, above).
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "codelldb" })
      if not IS_MACOS then
        vim.list_extend(opts.ensure_installed, { "rust-analyzer" })
      end
    end,
  },
}
