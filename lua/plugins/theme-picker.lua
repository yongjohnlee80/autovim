return {
  {
    name = "theme-picker",
    dir = vim.fn.stdpath("config"),
    lazy = true,
    keys = {
      {
        "<leader>ut",
        function()
          local themes = require("plugins.all-themes")
          local prefixes = {}
          for _, spec in ipairs(themes) do
            local key
            if spec.name then
              key = spec.name
            elseif type(spec[1]) == "string" then
              local short = spec[1]:match("([^/]+)$") or spec[1]
              key = short:gsub("%.nvim$", ""):gsub("%-neovim$", "")
            end
            if key then
              prefixes[key] = true
            end
          end
          -- `system` is our pseudo-theme in `colors/system.lua` — transparent
          -- revert-to-terminal look, also the fresh-install default.
          prefixes["system"] = true

          Snacks.picker.pick("colorschemes", {
            transform = function(item)
              local text = item.text
              for p, _ in pairs(prefixes) do
                if text == p or text:find("^" .. vim.pesc(p) .. "[-_]") then
                  return true
                end
              end
              return false
            end,
          })
        end,
        desc = "Theme Picker",
      },
    },
  },
}
