-- AutoDoc — the knowledge base, over AutoDoc's own Go daemon.
--
-- Plugin source: github.com/yongjohnlee80/autodoc. The Lua frontend ships
-- INSIDE the Go repo (lua/autodoc/**), so one checkout carries both the
-- plugin and the `cmd/autodoc` binary it drives.
--
-- ── Pin ────────────────────────────────────────────────────────────
-- Caret on the minor line, per the autovim-release-workflow pin policy:
-- tracks v0.1.x and refuses v0.2+ until the bump is explicit. v0.1.15 is
-- the first release with the Neovim plugin (ADR 1791209945).
--
-- ── Requires Go ────────────────────────────────────────────────────
-- The `build` hook compiles the daemon through the project's Makefile,
-- which sets `-buildvcs=false` (the family's bare+worktree layout trips
-- Go's nested-VCS rule) and the version stamp the daemon reports. If Go
-- is absent the hook fails loudly; install AutoDoc with Homebrew, mise or
-- `go install` instead and the plugin finds it on PATH.
--
-- ── What it brings ─────────────────────────────────────────────────
-- * The kb drawer. auto-finder's `kb` section hosts it BY AVAILABILITY
--   (auto-finder probes `autodoc.views.drawer`); without that section it
--   opens in AutoDoc's own panel (:AutodocDrawer).
-- * <leader>fk searches the selected KB (the project's primary KB unless
--   another was selected in the drawer).
-- * The Markdown preview: six slots on <leader>m*. It replaces
--   md-harpoon.nvim and md-render.nvim, which AutoVim no longer installs.
-- * :AutodocKbMigrate, to move a KB to the v2 layout.
--
-- ── State ──────────────────────────────────────────────────────────
-- `setup()` connects NOTHING. The first call that needs the daemon asks the
-- binary where it is and starts it when nothing serves the store, so
-- opening Neovim costs nothing. The daemon is shared with `autodoc --ui`
-- and every other Neovim instance.
return {
  {
    "yongjohnlee80/autodoc",
    version = "^0.1.0",
    build = "make build",
    dependencies = { "auto-core.nvim" },
    cmd = {
      "AutodocDrawer", "AutodocSearch", "AutodocSelect", "AutodocKbMigrate",
      "AutodocPreviewFocus", "AutodocPreviewRender", "AutodocPreviewRenderPath",
      "AutodocPreviewFind", "AutodocPreviewCloseAll", "AutodocPreviewBrowser",
    },
    ft = { "markdown", "markdown.mdx" },
    -- The stubs make lazy.nvim register the keys at startup and load the
    -- plugin on the first press; setup() (keys = true) then binds the same
    -- keys to their functions.
    keys = {
      { "<leader>fk", "<cmd>AutodocSearch<cr>", desc = "Search the KB (AutoDoc)" },
      { "<leader>mf", "<cmd>AutodocPreviewFind<cr>", desc = "Markdown: find file under cwd → pick panel" },
      { "<leader>mc", "<cmd>AutodocPreviewCloseAll<cr>", desc = "Markdown: close all preview floats" },
      { "<leader>mb", "<cmd>AutodocPreviewBrowser<cr>", desc = "Markdown: open in the browser" },
      { "<leader>m1", "<cmd>AutodocPreviewFocus 1<cr>", desc = "Markdown: upper left (1) — focus / open" },
      { "<leader>m2", "<cmd>AutodocPreviewFocus 2<cr>", desc = "Markdown: upper middle (2) — focus / open" },
      { "<leader>m3", "<cmd>AutodocPreviewFocus 3<cr>", desc = "Markdown: upper right (3) — focus / open" },
      { "<leader>ma", "<cmd>AutodocPreviewFocus a<cr>", desc = "Markdown: left (a) — focus / open" },
      { "<leader>ms", "<cmd>AutodocPreviewFocus s<cr>", desc = "Markdown: middle (s) — focus / open" },
      { "<leader>md", "<cmd>AutodocPreviewFocus d<cr>", desc = "Markdown: right (d) — focus / open" },
      { "<leader>m!", "<cmd>AutodocPreviewRender 1<cr>", desc = "Markdown: upper left (1) — render current" },
      { "<leader>m@", "<cmd>AutodocPreviewRender 2<cr>", desc = "Markdown: upper middle (2) — render current" },
      { "<leader>m#", "<cmd>AutodocPreviewRender 3<cr>", desc = "Markdown: upper right (3) — render current" },
      { "<leader>mA", "<cmd>AutodocPreviewRender a<cr>", desc = "Markdown: left (a) — render current" },
      { "<leader>mS", "<cmd>AutodocPreviewRender s<cr>", desc = "Markdown: middle (s) — render current" },
      { "<leader>mD", "<cmd>AutodocPreviewRender d<cr>", desc = "Markdown: right (d) — render current" },
    },
    opts = { keys = true },
    config = function(_, opts)
      require("autodoc").setup(opts)
    end,
  },
}
