return {
  "CRAG666/code_runner.nvim",
  keys = {
    { "<leader>cr", "<cmd>RunCode<cr>", desc = "Run Code" },
    { "<leader>cf", "<cmd>RunFile<cr>", desc = "Run File" },
  },
  opts = {
    filetype = {
      python = "python3",
      go = "go run",
      javascript = "node",
      typescript = "npx ts-node",
    },
    mode = "float",
    float = {
      close_key = "q",
      border = "rounded",
      blend = 0,
    },
  },
}