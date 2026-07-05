-- AI completion — GitHub Copilot as a blink.cmp source (ADR-0047 §B)
--
-- SHIPPED DISABLED. AI completion is opt-in in AutoVim: Copilot needs a
-- Copilot license + GitHub auth + Node >= 22, so it's off by default.
--
-- Enable WITHOUT editing this file — drop a file in lua/custom/plugins/
-- (lazy merges `enabled` by repo name over the stock specs below):
--
--   -- lua/custom/plugins/copilot.lua
--   return {
--     { "zbirenbaum/copilot.lua", enabled = true },
--     { "fang2hou/blink-copilot", enabled = true },
--   }
--
-- then :Lazy sync, restart, and :Copilot auth (verify with :Copilot status).
-- Copilot completions appear IN the blink menu (no inline ghost text), ranked
-- above LSP. Keep only one AI source on the menu at a time.

return {
  -- Copilot LSP client — its own inline suggestion + panel stay off (blink owns
  -- the completion surface).
  {
    "zbirenbaum/copilot.lua",
    enabled = false,
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
    },
  },

  -- The blink.cmp Copilot source (blink-async compliant; re-detects the Copilot
  -- LSP client on buffer switches).
  {
    "fang2hou/blink-copilot",
    enabled = false,
  },

  -- Register the source with blink — only when the source plugin is actually
  -- installed (i.e. Copilot was enabled above); otherwise leave blink untouched.
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      if not pcall(require, "blink-copilot") then
        return opts
      end
      opts.sources = opts.sources or {}
      opts.sources.default = opts.sources.default or {}
      if not vim.tbl_contains(opts.sources.default, "copilot") then
        table.insert(opts.sources.default, "copilot")
      end
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.copilot = {
        name = "copilot",
        module = "blink-copilot",
        score_offset = 100, -- rank Copilot above LSP results in the menu
        async = true,
      }
      return opts
    end,
  },
}
