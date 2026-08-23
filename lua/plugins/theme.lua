-- Colorscheme selection, unified across every platform on ONE branch.
--
-- History: the `omarchy` branch replaced this file with a SYMLINK to
-- `~/.config/omarchy/current/theme/neovim.lua`, which is why a per-OS branch
-- existed at all — a symlink is a tracked file, so it cannot be applied
-- conditionally. This version reads that same fragment at RUNTIME instead, so
-- Omarchy boxes get Omarchy's theme and everyone else gets the distribution
-- default, from a single `main`.
--
-- The choice itself lives in `utils.theme_resolve` as a pure function (see the
-- long comment there for why the Omarchy override rule is shaped the way it
-- is). This file only wires it up:
--   * declare Omarchy's own colorscheme plugin so its theme is installable
--   * resolve the name at apply time, so a pick made this session is honoured
--
-- Requirement 5: Omarchy follows the system theme unless overridden here;
-- every other platform defaults to `catppuccin-mocha`.

local platform = require("utils.platform")
local resolve = require("utils.theme_resolve")

-- Spec-time read, used only to declare Omarchy's colorscheme PLUGIN below.
-- The colorscheme NAME is resolved again at apply time so a system theme
-- switched after startup is still picked up.
local fragment = platform.omarchy_fragment()

local specs = {}

-- Carry Omarchy's own plugin declarations through, minus its `LazyVim/LazyVim`
-- entry (we own the colorscheme decision). Without this the theme Omarchy
-- names would be selected but never installed.
if fragment then
  for _, entry in ipairs(fragment) do
    if type(entry) == "table" and entry[1] and entry[1] ~= "LazyVim/LazyVim" then
      specs[#specs + 1] = entry
    end
  end
end

specs[#specs + 1] = {
  "LazyVim/LazyVim",
  opts = {
    -- Function form: evaluated when LazyVim applies the colorscheme, so the
    -- cache is read fresh rather than frozen at spec-build time.
    colorscheme = function()
      local name, reason = resolve.current()

      -- Surfaced for `:checkhealth`-style debugging and for the theme picker,
      -- which needs to know whether the current look is a system theme or an
      -- explicit override before it offers "follow system".
      vim.g.autovim_theme_name = name
      vim.g.autovim_theme_reason = reason

      if pcall(vim.cmd.colorscheme, name) then
        return
      end

      -- Degrade in order of decreasing opinion: the platform default, then the
      -- transparent `system` pseudo-theme in `colors/system.lua`, which needs
      -- no plugin and therefore cannot itself fail to install.
      vim.notify(
        ("theme '%s' failed to load, falling back"):format(name),
        vim.log.levels.WARN
      )
      for _, alt in ipairs({ resolve.FALLBACK, "system" }) do
        if alt ~= name and pcall(vim.cmd.colorscheme, alt) then
          vim.g.autovim_theme_name = alt
          vim.g.autovim_theme_reason = "fallback"
          return
        end
      end
    end,
  },
}

return specs
