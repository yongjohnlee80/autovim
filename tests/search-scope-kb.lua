-- tests/search-scope-kb.lua — `<leader>fK` / `<leader>sK` search the knowledge base.
--
-- They called `auto_core_var("KB_ROOT")`, a local that the move of the scope
-- resolvers into `utils.scope` took with it: every press raised "attempt to
-- call a nil value", and nothing tested the two keys, so it shipped. They now
-- read `utils.scope.kb_root()`, the resolver the rest of the file already uses.
--
-- The spec is loaded as lazy.nvim would load it, with LazyVim's picker and
-- auto-core's path variables stubbed, and each key's function is RUN.
local root = vim.fn.fnamemodify(
  vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h:h"), ":p")
package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local pass_count, fail_count = 0, 0
local function ok(n, c, d)
  if c then pass_count = pass_count + 1; io.stdout:write("  PASS  " .. n .. "\n")
  else fail_count = fail_count + 1
    io.stdout:write("  FAIL  " .. n .. (d and ("  — " .. tostring(d)) or "") .. "\n") end
  io.stdout:flush()
end

io.stdout:write("search scope — <leader>fK / <leader>sK search the KB root\n")

local vars = { WORKSPACE = "/ws", KB_ROOT = "/kb" }
package.loaded["auto-core.todo.vars"] = { get = function(name) return vars[name] end }
local opened, warned = {}, {}
_G.LazyVim = {
  pick = { open = function(cmd, o) opened[#opened + 1] = { cmd = cmd, cwd = o and o.cwd } end },
  warn = function(msg) warned[#warned + 1] = msg end,
}

local spec = dofile(root .. "lua/plugins/snacks-picker-search-scope.lua")
local keys = {}
for _, k in ipairs(spec[1].keys) do keys[k[1]] = k[2] end
ok("<leader>fK and <leader>sK are bound", type(keys["<leader>fK"]) == "function" and type(keys["<leader>sK"]) == "function")

local ran, err = pcall(keys["<leader>fK"])
ok("*** <leader>fK runs ***", ran, err)
ok("it opens the files picker at the KB root", opened[1] and opened[1].cmd == "files" and opened[1].cwd == "/kb",
  vim.inspect(opened[1]))
ran, err = pcall(keys["<leader>sK"])
ok("*** <leader>sK runs ***", ran, err)
ok("it opens live grep at the KB root", opened[2] and opened[2].cmd == "live_grep" and opened[2].cwd == "/kb",
  vim.inspect(opened[2]))

vars.KB_ROOT = nil
ran, err = pcall(keys["<leader>fK"])
ok("with no KB root it runs, opens nothing, and says why",
  ran and #opened == 2 and warned[1] and warned[1]:find("primary KB", 1, true) ~= nil, err or vim.inspect(warned))

ran, err = pcall(keys["<leader>ff"])
ok("the workspace pickers still open at the workspace", ran and opened[3] and opened[3].cwd == "/ws", err or vim.inspect(opened[3]))

io.stdout:write(("\n%d passed, %d failed\n"):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
