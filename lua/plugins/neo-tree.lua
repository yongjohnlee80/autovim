return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      {
        "<leader>e",
        "<cmd>Neotree source=workspace position=left toggle<cr>",
        desc = "Explorer: registered repos / worktrees",
      },
      {
        "<leader>E",
        function()
          require("neo-tree.command").execute({ toggle = true, dir = vim.uv.cwd() })
        end,
        desc = "Explorer NeoTree (cwd)",
      },
    },
    opts = {
      sources = { "filesystem", "buffers", "git_status", "neo-tree-workspace" },
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
