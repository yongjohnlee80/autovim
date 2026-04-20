-- Prepend a `repo [worktree-marker]` component to lualine's section_b so the
-- statusline shows `repo │ branch` with a trailing `(wt)` when the cwd is a
-- linked git worktree. Repo name comes from --git-common-dir (stable across
-- worktrees), not the worktree directory (which usually matches the branch).

local cache = { cwd = nil, repo = nil, worktree = false }

-- Turn a --git-common-dir path into a repo name:
--   /path/to/foo/.git   → foo         (standard repo)
--   /path/to/foo/.bare  → foo         (bare-in-subdir worktree layout)
--   /path/to/foo.git    → foo         (classic bare repo)
--   /path/to/foo        → foo         (anything else)
local function repo_name_from(common_dir)
  local base = vim.fn.fnamemodify(common_dir, ":t")
  if base == ".git" or base == ".bare" then
    return vim.fn.fnamemodify(common_dir, ":h:t")
  end
  if base:match("%.git$") then return (base:gsub("%.git$", "")) end
  return base
end

local function refresh()
  local cwd = vim.fn.getcwd()
  if cache.cwd == cwd then return end
  cache.cwd = cwd

  local common = vim.fn.systemlist({
    "git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir",
  })[1]
  if vim.v.shell_error ~= 0 or not common or common == "" then
    cache.repo, cache.worktree = nil, false
    return
  end

  cache.repo = repo_name_from((common:gsub("/$", "")))

  local toplevel = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })[1]
  cache.worktree = toplevel and toplevel ~= ""
    and vim.fn.filereadable(toplevel .. "/.git") == 1
end

local function repo_component()
  refresh()
  if not cache.repo then return "" end
  return cache.worktree and (cache.repo .. " (wt)") or cache.repo
end

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_b, 1, { repo_component, icon = "" })
      return opts
    end,
  },
}
