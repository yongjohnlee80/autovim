-- Two fixes stacked on nvim-lint so golangci-lint works after nvim's cwd
-- moves (e.g. <leader>gw into a worktree), not just from the dir nvim was
-- opened in.
--
-- Fix 1 -- dynamic filename_modifier on golangci-lint's args.
--   The bundled linter builds its `args` at plugin-load time by running
--   `go env GOMOD` at the current cwd and freezing a `filename_modifier`
--   (`:p` or `:h`) into a closure. Start nvim from a non-module parent
--   folder and that modifier stays `:p` forever, producing the wrong
--   argument shape after you :cd into a module. We surgically replace
--   just the function-arg inside the cached args with one that re-runs
--   the detection per invocation using an upward walk for go.mod.
--
-- Fix 2 -- cwd forced to the module root.
--   Even with correct args, golangci-lint's `typecheck` runs `go build`
--   under the hood, which needs the module context to resolve deps. The
--   try_lint override sets cwd to the enclosing go.mod's directory
--   (falls back to the buffer's dir for standalone files).
return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    local lint = require("lint")

    -- Walk up from the buffer's file looking for go.mod. Returns the
    -- directory containing go.mod, or nil if we're not inside a module.
    local function go_module_root(buf_path)
      if not buf_path or buf_path == "" then return nil end
      local dir = vim.fn.fnamemodify(buf_path, ":p:h")
      local found = vim.fs.find("go.mod", { upward = true, path = dir, type = "file" })[1]
      return found and vim.fn.fnamemodify(found, ":h") or nil
    end

    local golangci = lint.linters.golangcilint
    if golangci and type(golangci.args) == "table" then
      for i, arg in ipairs(golangci.args) do
        if type(arg) == "function" then
          golangci.args[i] = function()
            local buf_path = vim.api.nvim_buf_get_name(0)
            -- :h → package dir (when in a module), :p → absolute file path
            -- (standalone file outside any module). Matches the bundled
            -- logic but recomputes per invocation.
            local modifier = go_module_root(buf_path) and ":h" or ":p"
            return vim.fn.fnamemodify(buf_path, modifier)
          end
        end
      end
    end

    local orig_try_lint = lint.try_lint
    lint.try_lint = function(names, try_opts)
      try_opts = try_opts or {}
      local bufnr = try_opts.bufnr or vim.api.nvim_get_current_buf()
      if try_opts.cwd == nil and vim.bo[bufnr].filetype == "go" then
        local buf_path = vim.api.nvim_buf_get_name(bufnr)
        try_opts.cwd = go_module_root(buf_path)
          or vim.fn.fnamemodify(buf_path, ":p:h")
      end
      return orig_try_lint(names, try_opts)
    end

    return opts
  end,
}
