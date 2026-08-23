-- autodb — a database IDE for Neovim, over autodb's own Go daemon.
--
-- Plugin source: github.com/yongjohnlee80/autodb. The Lua frontend ships
-- INSIDE the Go repo (lua/autodb/**), so one checkout carries both the
-- plugin and the `cmd/autodb` binary it drives.
--
-- ── Pin ────────────────────────────────────────────────────────────
-- Caret on the minor line, per the autovim-release-workflow pin policy:
-- tracks v0.1.x automatically and refuses v0.2+ until the bump is
-- explicit. v0.1.0 is the first release, carrying M6 (backend + TUI) and
-- M7 (this frontend).
--
-- ── Requires Go ────────────────────────────────────────────────────
-- The `build` hook compiles the daemon through the project's Makefile,
-- which owns two things a hand-written `go build` here would lose:
--   * `-buildvcs=false` — the family's bare+worktree layout trips Go's
--     nested-VCS rule
--   * `-ldflags -X main.version=…` — the version stamp that autodb's
--     stale-backend check compares against the RUNNING daemon
-- If Go is absent the hook fails loudly; install autodb via Mason or
-- `go install` instead and the plugin will find it on PATH.
--
-- ── The dbase explorer ─────────────────────────────────────────────
-- auto-finder's `dbase` slot switches from nvim-dbee to autodb's own
-- tree BY AVAILABILITY — installing this plugin is the cutover, and
-- uninstalling it reverses it. No configuration links the two. The
-- switch happens because auto-finder's slot does
-- `pcall(require, "autodb.session")`, and lazy.nvim's module loader
-- turns that require into an on-demand load, so lazy-by-default is
-- preserved.
--
-- dbee was retired in v0.4.0 (M8): AutoVim no longer declares, installs or
-- updates it, and it is not a fallback. autodb is the only dbase backend.
-- Historical note — the M7 step merely stopped mounting dbee's drawer; the
-- removal itself landed with the autovim minor
-- bump.
--
-- ── Keys ───────────────────────────────────────────────────────────
-- The plugin binds the `<leader>D` set itself in `setup()`. The entries
-- below exist so lazy.nvim registers the prefixes at startup and defers
-- loading until first use; on load, `setup()` rebinds them to direct
-- functions. Same keys, same behaviour — the stubs only decide WHEN the
-- plugin loads. Pass `keys = { run_buffer = false, … }` to `opts` to
-- suppress any individual binding and own it here instead.
--
--   <leader>Dr   run this SQL buffer      <leader>Dc   choose a connection
--   <leader>DR   run the selection        <leader>Dh   script history
--   <leader>Dw   choose / create workspace <leader>Dn   choose / create note
--   <leader>Dl   sign in (retry)            <leader>DX   maintenance
--
-- ── State ──────────────────────────────────────────────────────────
-- `setup()` connects NOTHING. The first `<leader>D` command resolves the
-- binary, starts the daemon if none is listening, and prompts for a
-- passphrase — masked, via `inputsecret()`. Opening Neovim costs nothing.
--
-- Get the passphrase wrong and `<leader>Dl` prompts again on the same
-- live socket; it also switches user on a daemon that is already signed
-- in. Recovering from a typo does not cost a restart.
--
-- The daemon listens on a unix socket (0600, per-user directory) and is
-- SHARED with `autodb --ui` and every other Neovim instance. Configure
-- `[server] port` in autodb's own config.toml to opt into TCP instead.

return {
  {
    "yongjohnlee80/autodb",
    -- Caret pin: tracks v0.1.x, refuses v0.2+ unprompted.
    version = "^0.1.0",
    build = "make build",
    dependencies = { "auto-core.nvim" },
    cmd = { "AutodbRun", "AutodbConnection", "AutodbHistory", "AutodbLogin",
      "AutodbWorkspace", "AutodbNote", "AutodbMaintenance" },
    keys = {
      { "<leader>Dr", "<cmd>AutodbRun<cr>", desc = "autodb: run this SQL buffer" },
      { "<leader>DR", ":AutodbRun<cr>", mode = "v", desc = "autodb: run the selection" },
      { "<leader>Dw", "<cmd>AutodbWorkspace<cr>", desc = "autodb: choose / create a workspace" },
      { "<leader>Dn", "<cmd>AutodbNote<cr>", desc = "autodb: choose / create a note" },
      { "<leader>Dc", "<cmd>AutodbConnection<cr>", desc = "autodb: choose a connection" },
      { "<leader>Dh", "<cmd>AutodbHistory<cr>", desc = "autodb: script history" },
      { "<leader>Dl", "<cmd>AutodbLogin<cr>", desc = "autodb: sign in" },
      { "<leader>DX", "<cmd>AutodbMaintenance<cr>", desc = "autodb: maintenance" },
    },
    opts = {},
    config = function(_, opts)
      require("autodb").setup(opts)
    end,
  },

  -- SQL highlighting is autodb's own requirement.
  --
  -- The `sql` parser used to be requested by lua/plugins/nvim-dbee.lua, so
  -- deleting that file in M8 would have silently taken SQL highlighting with
  -- it — a regression flagged in ADR-0058 §2 and pre-empted by requesting it
  -- here too. dbee is now gone (v0.4.0) and this is the ONLY request, which is
  -- exactly why it has to stay: scripts, notes and the history preview are all
  -- SQL buffers.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "sql" })
    end,
  },
}
