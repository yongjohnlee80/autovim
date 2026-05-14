-- auto-core.nvim — foundation library for the AutoVim plugin family.
--
-- Plugin source: github.com/yongjohnlee80/auto-core.nvim. Pinned via
-- `version = "^0.1.0"` (caret) so lazy.nvim auto-tracks v0.1.x
-- patch + minor releases (additive-only per the auto-core-maintenance
-- convention) and refuses to cross to v0.2+ unprompted.
--
-- Other AutoVim plugins (auto-agents, auto-finder, md-harpoon,
-- worktree) reference auto-core in their `dependencies` block by
-- NAME ("auto-core.nvim") rather than redeclaring the spec — lazy.nvim
-- merges by name and resolves to this top-level entry, so the version
-- pin propagates.
--
-- For local development against ~/Source/Projects/nvim-plugins/auto-core.nvim,
-- swap the spec line for:
--     dir = vim.fn.expand("~/Source/Projects/nvim-plugins/auto-core.nvim/<worktree>"),
--     name = "auto-core.nvim",
-- and lazy will use the working copy on `:Lazy reload auto-core.nvim`.
--
-- Subsystems exposed (v0.1.5 — mailbox phase 1 landed):
--   M.events  - pub/sub bus + topic registry + ring-buffer trace
--   M.state   - namespaced store with json/ephemeral persist
--   M.ui      - panel / winbar / section / float / float.multi / highlights
--   M.fs      - path / watch / tree
--   M.git     - repo / status / worktree / graph / fetch / pull
--   M.tasks   - queue / channel / status / :AutoCoreChannel UI
--   M.log     - structured logger (drop-in for auto-agents.logger)
--   M.lsp     - tech-stack-aware reset on workspace switch
--   M.files   - global show_hidden / show_dotfiles prefs
--   M.health  - :checkhealth auto-core
--   M.debug   - opt-in winlog + mailbox diagnostic probes
--   M.mailbox - file-backed cross-process transport, router,
--               command registry, executioner, viewer (ADR 0013)
--
-- Stability contract: every v0.X.Y from v0.1.0 forward is additive
-- only — no renames, removals, or break-shape changes to existing
-- functions, state-namespace keys, event topics, or persisted
-- schemas. See the `auto-core-maintenance` convention in the
-- auto-agents kb for the full eleven-rule contract.

return {
  {
    "yongjohnlee80/auto-core.nvim",
    -- Caret pin: tracks v0.1.x (auto-update within the minor line),
    -- refuses v0.2+ until the bump is explicit.
    version = "^0.1.0",
    -- plenary is auto-core's only hard dep per ADR §"Resolutions" #3.
    dependencies = { "nvim-lua/plenary.nvim" },
    -- No `lazy = false` — auto-core loads on demand when a consumer
    -- requires it. Setup is consumer-driven; we don't call it here.
  },
}
