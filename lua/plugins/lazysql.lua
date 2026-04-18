return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<C-q>",
        function()
          Snacks.terminal.toggle("lazysql", {
            win = { style = "lazygit" },
          })
        end,
        mode = { "n", "t" },
        desc = "LazySQL",
      },
    },
  },
}
