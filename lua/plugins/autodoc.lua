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
-- ── The binary ─────────────────────────────────────────────────────
-- The plugin's build.lua installs bin/autodoc: the release binary built
-- for the plugin's own tag, checksummed (no Go, no Command Line Tools;
-- macOS's is built with cgo, so it keeps the FSEvents watcher). Off a tag,
-- offline, or on a platform without one it falls back to `make build`,
-- which needs Go. One binary per machine: make the TUI's `autodoc` on
-- PATH this one (<leader>mX → versions says so, with the `ln -sf`), or a
-- TUI of another build restarts the shared daemon as itself.
--
-- ── The daemon ─────────────────────────────────────────────────────
-- A daemon older than the plugin is offered a restart as the plugin's
-- build, once (ADR 1791209945 §3.1); <leader>mX restarts it at will.
--
-- ── What it brings ─────────────────────────────────────────────────
-- * The kb drawer. auto-finder's `kb` section hosts it BY AVAILABILITY
--   (auto-finder probes `autodoc.views.drawer`); without that section it
--   opens in AutoDoc's own panel (:AutodocDrawer).
-- * <leader>m, the knowledge base: mf search the selected KB (the
--   project's primary unless another was chosen), mF a document by name,
--   mr recent files (shared with `autodoc --ui`), ml what links to this
--   file, mk the kb drawer, mw choose the KB to search, mX maintenance.
--   <leader>fk searches too.
-- * The Markdown preview, on the same group: six slots (m1 m2 m3 ma ms md
--   focus, m! m@ m# mA mS mD render), mp find a Markdown file under the
--   cwd, mc close all, mb the browser. It replaces md-harpoon.nvim and
--   md-render.nvim, which AutoVim no longer installs.
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
    build = "build.lua",
    dependencies = { "auto-core.nvim" },
    cmd = {
      "AutodocDrawer", "AutodocSearch", "AutodocSelect", "AutodocKbMigrate",
      "AutodocFiles", "AutodocRecent", "AutodocBacklinks", "AutodocMaintenance",
      "AutodocPreviewFocus", "AutodocPreviewRender", "AutodocPreviewRenderPath",
      "AutodocPreviewFind", "AutodocPreviewCloseAll", "AutodocPreviewBrowser",
    },
    ft = { "markdown", "markdown.mdx" },
    -- The stubs make lazy.nvim register the keys at startup and load the
    -- plugin on the first press; setup() (keys = true) then binds the same
    -- keys to their functions.
    keys = {
      { "<leader>mf", "<cmd>AutodocSearch<cr>", desc = "KB: search (lexical + semantic + rerank)" },
      { "<leader>mF", "<cmd>AutodocFiles<cr>", desc = "KB: find a document by name" },
      { "<leader>mr", "<cmd>AutodocRecent<cr>", desc = "KB: recent files" },
      { "<leader>ml", "<cmd>AutodocBacklinks<cr>", desc = "KB: what links to this file" },
      { "<leader>mk", "<cmd>AutodocDrawer<cr>", desc = "KB: the kb drawer" },
      { "<leader>mw", "<cmd>AutodocSelect<cr>", desc = "KB: choose the KB to search" },
      { "<leader>mX", "<cmd>AutodocMaintenance<cr>", desc = "KB: maintenance (restart, install, versions)" },
      { "<leader>fk", "<cmd>AutodocSearch<cr>", desc = "Search the KB (AutoDoc)" },
      { "<leader>mp", "<cmd>AutodocPreviewFind<cr>", desc = "Markdown: find file under cwd → pick panel" },
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
