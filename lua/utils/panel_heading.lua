-- The heading above the auto-finder panel: which checkout you are working in.
--
-- Johno, 2026-09-08: "on top of the winbar displays the 'auto-finder', I would
-- also like to display the current worktree path we are working on. Let's say
-- if I'm on a workspace directory just display the directory title like
-- 'auto-finder: [nvim-plugins]', but [if] the current working directory
-- (retrieved from auto-core, the path set by <leader>gw) is git repository it
-- should display 'auto-finder: [repo-name - branch/worktree name]'. If the
-- text value is too long, we should hide the prefix 'auto-finder: ' and
-- display ellipsis."
--
-- WHERE THIS IS DRAWN, because it is not where it looks: that heading is
-- bufferline.nvim's sidebar `offset` text, NOT a winbar. The winbar is only
-- the `0 1 2 [N: view]` tab strip, which auto-core renders. bufferline shows
-- an offset's text when the TOP-LEFT window's buffer filetype matches a
-- configured entry, which is why the config lives in
-- `lua/plugins/bufferline.lua` and why this module is autovim's rather than
-- the plugin's.
--
-- WHY IT IS A MODULE and not a closure in that spec: it has real behaviour to
-- pin — three resolution cases, a truncation ladder, and a cache — and a
-- closure inside a lazy spec is unreachable from a headless suite.

local M = {}

---The prefix dropped first when space runs out. The panel is already
---identifiable by its position and its contents; WHICH repo you are in is the
---information, so it is the part that survives.
M.PREFIX = "auto-finder: "

---Filetypes the auto-finder panel window can carry. Must stay in step with
---the bufferline offset entries — they answer the same question ("is that
---window the panel?") and the width lookup here has to agree with the width
---bufferline measured, or the truncation would be computed against a
---different column count than the one it is drawn into.
M.FILETYPES = { ["auto-finder"] = true, ["auto-finder-config"] = true }

---Resolution costs three `git rev-parse` reads, and the tabline redraws
---constantly — on every buffer switch, window change and `:redrawtabline`. So
---the answer is cached against the CHEAP part of the question: the directory
---the label is derived from, which is a table lookup and a `getcwd`.
---
---No event subscription: a worktree switch changes the key, and the next
---redraw recomputes. An invalidation hook would be a second mechanism that
---could disagree with the key.
---@type { key: string?, label: string? }
local _cache = { key = nil, label = nil }

---Drop the cache. For tests, and for a caller that knows something changed
---that the key cannot see (a branch renamed under the same path).
function M.invalidate()
  _cache = { key = nil, label = nil }
end

---The directory the label describes: the worktree `<leader>gw` last switched
---to, else the cwd.
---
---`utils.scope` owns this question — the module that exists precisely because
---several LazyVim entry points resolved "the project" from the focused buffer
---and kept retargeting into the knowledge base. Asking it here rather than
---walking up for a `.git` keeps the heading naming the same checkout the git
---pickers and lazygit act on.
---@return string
function M.scope_dir()
  local ok, scope = pcall(require, "utils.scope")
  if ok and type(scope.active_worktree) == "function" then
    local wt = scope.active_worktree()
    if type(wt) == "string" and wt ~= "" then return wt end
  end
  return vim.fn.getcwd()
end

---The repo's NAME, from the label `auto-core.git.graph` produced.
---
---`graph.repo_label` answers a different question than this heading asks, and
---it is right to. For the REPOS PANEL it returns a path when that path
---disambiguates: relative to the workspace root for a repo underneath it
---(`sub/dir/thing.nvim`), and `~`-shortened for one outside it
---(`~/.config/nvim`). A panel with 100 columns and a tree of repos wants that.
---
---A 38-column heading does not. MEASURED against the live workspace on
---2026-09-08, before this trim existed:
---
---  [~/Source/Projects/nvim-plugins/autovim - feat/panel-titles-and-finder-scope]
---
---Johno asked for "[repo-name - branch/worktree name]", and that is a path,
---not a name. It appears whenever the repo is not under the resolved workspace
---root — which is not an edge case: it is every repo reached before the first
---`<leader>gw` of the session, the nvim runtime clone, and the knowledge base.
---
---So the heading takes the last segment. The disambiguation is not lost, it is
---delegated: the repos panel directly below shows the full label, and the
---branch is on this line already.
---
---MY OWN SUITE MISSED THIS, which is the part worth keeping. A cell asserted
---`repo_label(...) == vim.fn.fnamemodify("/elsewhere/other", ":~")` — it
---encoded auto-core's behaviour as correct FOR THIS CONSUMER without asking
---whether a path is what a heading wants. It agreed with the wrong property.
---An independent probe against the real workspace, using none of the
---fixtures, is what found it.
---@param label string
---@return string
function M.repo_name(label)
  if type(label) ~= "string" or label == "" then return label end
  local trimmed = label:gsub("/+$", "")
  -- NEVER return empty. A label of "/" (or all slashes) trims to nothing and
  -- has no last segment, which would render "[ - main]" — worse than the path
  -- this function exists to shorten. Fall back to what we were given.
  local seg = trimmed:match("([^/]+)$")
  if seg and seg ~= "" then return seg end
  return label
end

---Resolve `dir` to a bracketed label. Uncached; `scope_label` is the entry
---point.
---@param dir string
---@return string
function M.resolve(dir)
  local root
  local ok_scope, scope = pcall(require, "utils.scope")
  if ok_scope and type(scope.workspace_root) == "function" then
    local okr, r = pcall(scope.workspace_root)
    if okr and type(r) == "string" then root = r end
  end

  -- auto-core answers "which repo am I in", including the bare + linked
  -- worktree layout this workspace is built from — where the checkout
  -- directory (`main`, `panel-titles`) is NOT the repo name. Delegated rather
  -- than re-derived: the repos panel labels repos with the same function, and
  -- a heading disagreeing with the panel below it would be its own bug.
  local ok_graph, graph = pcall(require, "auto-core.git.graph")
  if ok_graph and type(graph.repo_at) == "function" then
    local okr, repo = pcall(graph.repo_at, dir, root)
    if okr and type(repo) == "table" and repo.label then
      -- The branch, or the checkout's directory name when HEAD is detached.
      -- A detached worktree has no branch, and printing the literal "HEAD"
      -- would read like a branch called that.
      local wt_name = repo.branch
      if not wt_name or wt_name == "" then
        wt_name = vim.fn.fnamemodify(repo.worktree or dir, ":t")
      end
      return ("[%s - %s]"):format(M.repo_name(repo.label), wt_name)
    end
  end

  -- Not a repo: a plain directory, or — the case this workspace actually is —
  -- a CONTAINER of repos. `~/Source/Projects/nvim-plugins` holds eleven of
  -- them and carries an empty `.git/` that fools every existence check while
  -- git still refuses it, so "is it a repo" has to be git's answer, which is
  -- what `repo_at` returning nil above is.
  local d = (dir ~= "" and dir) or root or vim.fn.getcwd()
  return ("[%s]"):format(vim.fn.fnamemodify((d:gsub("/+$", "")), ":t"))
end

---The bracketed scope label, cached.
---@return string
function M.scope_label()
  local key = M.scope_dir()
  if _cache.key == key and _cache.label then return _cache.label end
  local label = M.resolve(key)
  _cache.key, _cache.label = key, label
  return label
end

---Shorten `s` to at most `cells` display cells, keeping the bracket framing
---and marking the cut with an ellipsis.
---
---Shrinks by CHARACTER and re-measures, rather than assuming one cell per
---character: a repo or branch name can hold a wide glyph, and slicing by
---byte or by char count would overrun the column bufferline reserved.
---@param s string      a "[…]" label
---@param cells integer
---@return string
function M.ellipsize(s, cells)
  if cells <= 0 then return "" end
  if vim.api.nvim_strwidth(s) <= cells then return s end

  local open, close, inner = "", "", s
  if s:sub(1, 1) == "[" and s:sub(-1) == "]" then
    open, close, inner = "[", "]", s:sub(2, -2)
  end
  local frame = vim.api.nvim_strwidth(open .. "…" .. close)
  -- Not even the frame fits: hand back a hard cut of the whole string, since
  -- an empty heading says less than a mangled one.
  if frame >= cells then
    local out = s
    while #out > 0 and vim.api.nvim_strwidth(out) > cells do
      out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
    end
    return out
  end

  local budget = cells - frame
  while vim.fn.strchars(inner) > 0 and vim.api.nvim_strwidth(inner) > budget do
    inner = vim.fn.strcharpart(inner, 0, vim.fn.strchars(inner) - 1)
  end
  return open .. inner .. "…" .. close
end

---The width available to the heading, or nil when the panel is not visible.
---
---bufferline sizes an offset from the matching window and then draws the text
---into `size - 2` columns (one padding column each side), so the same figure
---is what the truncation ladder has to be measured against.
---@return integer? cells
function M.available_width()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local ok_buf, b = pcall(vim.api.nvim_win_get_buf, w)
    if ok_buf and M.FILETYPES[vim.bo[b].filetype] then
      local ok_cfg, cfg = pcall(vim.api.nvim_win_get_config, w)
      -- Floating windows are never the offset's window: bufferline matches
      -- the top-left window of the LAYOUT.
      if ok_cfg and (cfg.relative == nil or cfg.relative == "") then
        return math.max(0, vim.api.nvim_win_get_width(w) - 2)
      end
    end
  end
  return nil
end

---The heading text.
---
---A ladder, widest first, because each rung sheds the least useful thing left:
---  1. `auto-finder: [repo - branch]`  — everything
---  2. `[repo - branch]`               — the prefix goes; the panel is already
---                                       identifiable without being named
---  3. `[repo - bran…]`                — the scope itself is cut, from the
---                                       right, so the repo name survives
---@param cells integer?  available columns; nil = no limit (unknown width)
---@return string
function M.heading(cells)
  local label = M.scope_label()
  local full = M.PREFIX .. label
  if cells == nil then return full end
  if vim.api.nvim_strwidth(full) <= cells then return full end
  if vim.api.nvim_strwidth(label) <= cells then return label end
  return M.ellipsize(label, cells)
end

---What the bufferline offset's `text` field calls: the heading at whatever
---width the panel currently has.
---@return string
function M.text()
  return M.heading(M.available_width())
end

return M
