-- tests/cursor-visibility.lua — smear-cursor stays gone, in BOTH halves.
--
-- Removing a plugin is two edits that can drift apart: the spec in
-- lua/plugins/, and the entry in lazy-lock.json. Drop only the spec and the
-- lock keeps a "ghost entry" (release playbook §4d); drop only the lock and a
-- fresh install silently has no pin. smoke.lua §13 catches the second shape —
-- caret-pinned but unlocked — and nothing catches the first, so it goes here.
--
-- beacon.nvim is asserted PRESENT in the same terms. That is the positive
-- control: without it, every "smear is absent" assertion below would still
-- pass if the scan or the lock parse silently found nothing at all.
local root = vim.fn.fnamemodify(
  vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h:h"), ":p")

local pass_count, fail_count = 0, 0
local function ok(n, c, d)
  if c then pass_count = pass_count + 1; io.stdout:write("  PASS  " .. n .. "\n")
  else fail_count = fail_count + 1
    io.stdout:write("  FAIL  " .. n .. (d and ("  — " .. tostring(d)) or "") .. "\n") end
  io.stdout:flush()
end

io.stdout:write("cursor visibility — smear-cursor removed, beacon retained\n")

-- Which spec files name a plugin, by its GitHub path (what lazy resolves on).
local function specs_naming(needle)
  local hits = {}
  for _, f in ipairs(vim.fn.glob(root .. "lua/plugins/*.lua", false, true)) do
    local body = table.concat(vim.fn.readfile(f), "\n")
    if body:find(needle, 1, true) then hits[#hits + 1] = vim.fn.fnamemodify(f, ":t") end
  end
  return hits
end

io.stdout:write("\n[1] the scan works at all (positive control)\n")
local spec_files = vim.fn.glob(root .. "lua/plugins/*.lua", false, true)
ok("there are spec files to scan", #spec_files > 10, #spec_files)
local beacon_specs = specs_naming("DanilaMihailov/beacon.nvim")
ok("*** the scan FINDS beacon, so an empty result means absent ***",
  #beacon_specs == 1, vim.inspect(beacon_specs))

io.stdout:write("\n[2] the lock parses at all (positive control)\n")
local lock_raw = table.concat(vim.fn.readfile(root .. "lazy-lock.json"), "\n")
local lock_ok, lock = pcall(vim.json.decode, lock_raw)
ok("lazy-lock.json is valid JSON", lock_ok and type(lock) == "table")
ok("it holds a plausible number of entries", lock_ok and vim.tbl_count(lock) > 30,
  lock_ok and vim.tbl_count(lock) or "n/a")
ok("*** the lock CONTAINS beacon, so a nil lookup means absent ***",
  lock_ok and lock["beacon.nvim"] ~= nil)

io.stdout:write("\n[3] smear-cursor is gone from both halves\n")
local smear_specs = specs_naming("sphamba/smear-cursor.nvim")
ok("*** no spec declares smear-cursor ***", #smear_specs == 0, vim.inspect(smear_specs))
ok("*** no lazy-lock.json entry for smear-cursor (no ghost entry) ***",
  lock_ok and lock["smear-cursor.nvim"] == nil)
-- A QUOTED plugin path is what lazy resolves on, so that — not the bare name —
-- is the thing that must be absent. The removal note above cursor-visibility's
-- spec names the plugin in prose deliberately, and a bare-name scan failed on
-- it: the guard has to separate documentation from a live reference.
local function quoted_refs(path)
  local hits = {}
  for _, f in ipairs(vim.fn.glob(root .. "lua/**/*.lua", false, true)) do
    local body = table.concat(vim.fn.readfile(f), "\n")
    if body:find('"' .. path .. '"', 1, true) then
      hits[#hits + 1] = vim.fn.fnamemodify(f, ":t")
    end
  end
  return hits
end
ok("control: a quoted path scan finds beacon across all of lua/",
  #quoted_refs("DanilaMihailov/beacon.nvim") == 1,
  vim.inspect(quoted_refs("DanilaMihailov/beacon.nvim")))
ok("*** no quoted smear-cursor path anywhere in lua/ ***",
  #quoted_refs("sphamba/smear-cursor.nvim") == 0,
  vim.inspect(quoted_refs("sphamba/smear-cursor.nvim")))

io.stdout:write("\n[4] beacon survives, and is loadable as a spec\n")
-- The load-bearing check. Sections [1]-[3] scan TEXT, and this file's own
-- header quotes both plugin paths in prose (the "turn it off" example), so a
-- text scan cannot fully separate a live spec from a mention: measured by
-- mutation, renaming beacon in the spec table left the [1]/[3] controls green
-- because the comment still matched, and only the cell below went red. Treat
-- the scans as guards against a forgotten entry, and this as the assertion
-- about what lazy actually resolves.
local chunk = assert(loadfile(root .. "lua/plugins/cursor-visibility.lua"))
local spec = assert(chunk())
ok("cursor-visibility.lua returns a spec list", type(spec) == "table" and #spec >= 1, #spec)
ok("its only entry is beacon", #spec == 1 and spec[1][1] == "DanilaMihailov/beacon.nvim",
  vim.inspect(vim.tbl_map(function(s) return s[1] end, spec)))
ok("beacon keeps its configured opts", type(spec[1].opts) == "table"
  and spec[1].opts.min_jump == 10 and spec[1].opts.winblend == 60,
  vim.inspect(spec[1].opts))

io.stdout:write(("\n%d passed, %d failed\n"):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
