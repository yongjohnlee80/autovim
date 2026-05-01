return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      window = {
        width = function()
          return math.min(40, math.floor(vim.o.columns / 3))
        end,
      },
      filesystem = {
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
        },
        check_gitignore_in_search = false,
        components = {
          name = function(config, node, state)
            local cc = require("neo-tree.sources.common.components")
            local result = cc.name(config, node, state)
            local name = node.name or ""
            if node.type ~= "directory" and name:sub(1, 1) == "." then
              result.highlight = "NeoTreeDotfile"
            end
            return result
          end,
        },
      },
    },
  },
}
