-- Dart / Flutter editor support (ADR 0196 r3 §2.1).
--
-- AutoVim ADOPTS LazyVim's `lang.dart` extra (lazyvim.json): unlike `lang.rust`,
-- it passes the audit. It wires dartls through the ordinary `opts.servers`
-- idiom, adds the `dart` Treesitter parser and `dart format`, and owns no LSP
-- client, no DAP and no keymaps. Its neotest fragment is `optional` and inert
-- here (AutoVim has no neotest). Run / test / debug belong to auto-run.nvim's
-- `dart` adapter, which drives the SDK's own debug adapters.
--
-- This overlay carries only what the extra cannot know: dartls ships WITH the
-- Dart / Flutter SDK (`dart language-server`) and is not a Mason package, so
-- no install is attempted. Install the SDK and put it on PATH, the same
-- posture as the Go toolchain.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        dartls = { mason = false },
      },
    },
  },
}
