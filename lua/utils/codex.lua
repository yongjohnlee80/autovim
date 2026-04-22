local M = {}

local OUTPUT_BUF_NAME = "codex://output"
local PATCH_BUF_PREFIX = "codex://patch/"
local MAX_CONTEXT_CHARS = 20000
local patch_seq = 0

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Codex" })
end

local function ensure_codex()
  if vim.fn.executable("codex") == 1 then
    return true
  end
  notify("codex is not available on PATH", vim.log.levels.ERROR)
  return false
end

local function trim(text)
  return vim.trim(text or "")
end

local function root_fallback(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local dir = name ~= "" and vim.fn.fnamemodify(name, ":p:h") or vim.fn.getcwd()
  local git_dir = vim.fs.find(".git", { upward = true, path = dir })[1]
  return git_dir and vim.fn.fnamemodify(git_dir, ":h") or dir
end

function M.project_root(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if rawget(_G, "LazyVim") and LazyVim.root and LazyVim.root.get then
    return LazyVim.root.get({ buf = buf, normalize = true })
  end
  return root_fallback(buf)
end

function M.project_name(root)
  root = root or M.project_root()
  return vim.fn.fnamemodify(root, ":t")
end

function M.launcher_path()
  return vim.fn.stdpath("config") .. "/bin/codex-nvim"
end

function M.terminal_command(opts)
  opts = opts or {}
  local cmd = { M.launcher_path() }
  if opts.trusted then
    cmd[#cmd + 1] = "--trusted"
  end
  if opts.force_new then
    cmd[#cmd + 1] = "--new"
  end
  cmd[#cmd + 1] = "--no-alt-screen"
  return cmd
end

local function relative_path(path, root)
  if path == "" then
    return "[No Name]"
  end

  root = root or M.project_root()
  local prefix = root:gsub("/+$", "") .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return vim.fn.fnamemodify(path, ":~:.")
end

local function truncate_context(text)
  if #text <= MAX_CONTEXT_CHARS then
    return text
  end

  return text:sub(1, MAX_CONTEXT_CHARS) .. ("\n\n[context truncated after %d characters]"):format(MAX_CONTEXT_CHARS)
end

local function ensure_output_buf()
  local buf = vim.fn.bufnr(OUTPUT_BUF_NAME)
  if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, OUTPUT_BUF_NAME)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false
  return buf
end

local function open_output(title, lines)
  local buf = ensure_output_buf()
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    vim.cmd("botright 14split")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  else
    vim.api.nvim_set_current_win(win)
  end

  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_win_set_height(win, math.max(12, math.floor(vim.o.lines * 0.25)))

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

local function open_error_output(title, stderr)
  local lines = {
    "# " .. title,
    "",
    "## Stderr",
    "",
  }

  if stderr ~= "" then
    vim.list_extend(lines, vim.split(stderr, "\n", { plain = true }))
  else
    lines[#lines + 1] = "_No stderr output returned._"
  end

  open_output(title, lines)
end

local function parse_exec_output(stdout)
  local messages = {}
  local usage

  for line in (stdout or ""):gmatch("[^\r\n]+") do
    local ok, item = pcall(vim.json.decode, line)
    if ok and type(item) == "table" then
      if item.type == "item.completed" and type(item.item) == "table" then
        if item.item.type == "agent_message" and type(item.item.text) == "string" then
          messages[#messages + 1] = item.item.text
        end
      elseif item.type == "turn.completed" and type(item.usage) == "table" then
        usage = item.usage
      end
    end
  end

  return table.concat(messages, "\n\n"), usage
end

local function format_output(opts)
  local lines = {
    "# " .. opts.title,
    "",
    ("- Root: `%s`"):format(opts.root),
  }

  if opts.source then
    lines[#lines + 1] = ("- Source: `%s`"):format(opts.source)
  end

  lines[#lines + 1] = ("- Sandbox: `%s`"):format(opts.sandbox)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Prompt"
  lines[#lines + 1] = ""
  lines[#lines + 1] = opts.prompt
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Response"
  lines[#lines + 1] = ""

  if opts.response ~= "" then
    vim.list_extend(lines, vim.split(opts.response, "\n", { plain = true }))
  else
    lines[#lines + 1] = "_No response text returned._"
  end

  if opts.usage then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Usage"
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("- Input tokens: `%s`"):format(opts.usage.input_tokens or "?")
    lines[#lines + 1] = ("- Cached input tokens: `%s`"):format(opts.usage.cached_input_tokens or 0)
    lines[#lines + 1] = ("- Output tokens: `%s`"):format(opts.usage.output_tokens or "?")
  end

  if opts.stderr ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Stderr"
    lines[#lines + 1] = ""
    vim.list_extend(lines, vim.split(opts.stderr, "\n", { plain = true }))
  end

  return lines
end

local function run_exec_capture(request, opts, on_complete)
  opts = opts or {}
  if not ensure_codex() then
    return
  end

  local prompt = trim(request)
  if prompt == "" then
    return
  end

  local root = opts.root or M.project_root(opts.buf)
  local sandbox = opts.workspace_write and "workspace-write" or "read-only"
  local title = opts.title or "Codex Exec"
  local source = opts.source
  local output_path = vim.fn.tempname()

  notify(("Running %s for %s"):format(title, M.project_name(root)))

  vim.system({
    "codex",
    "exec",
    "--json",
    "--color",
    "never",
    "--ephemeral",
    "--skip-git-repo-check",
    "--sandbox",
    sandbox,
    "--output-last-message",
    output_path,
    "-C",
    root,
    "-",
  }, {
    stdin = prompt,
    text = true,
  }, function(obj)
    local parsed_response, usage = parse_exec_output(obj.stdout)
    local response = parsed_response
    local stat = vim.uv.fs_stat(output_path)
    if stat then
      -- Prefer the --output-last-message file only when it actually has
      -- content. Some failure modes leave it empty and we'd otherwise throw
      -- away the messages we already parsed from the JSON stream.
      if stat.size and stat.size > 0 then
        response = table.concat(vim.fn.readfile(output_path), "\n")
      end
      vim.fn.delete(output_path)
    end
    vim.schedule(function()
      on_complete({
        code = obj.code,
        root = root,
        title = title,
        source = source,
        sandbox = sandbox,
        prompt = prompt,
        response = response,
        stderr = trim(obj.stderr),
        usage = usage,
      })
    end)
  end)
end

local function run_exec(request, opts)
  run_exec_capture(request, opts, function(result)
    local lines = format_output({
      title = result.title,
      root = result.root,
      source = result.source,
      sandbox = result.sandbox,
      prompt = result.prompt,
      response = result.response,
      stderr = result.stderr,
      usage = result.usage,
    })

    open_output(result.title, lines)
    if result.code == 0 then
      notify(("%s completed"):format(result.title))
    else
      notify(("%s failed with exit code %d"):format(result.title, result.code), vim.log.levels.ERROR)
    end
  end)
end

local function ask_for_prompt(prompt_text, on_submit)
  vim.ui.input({ prompt = prompt_text }, function(input)
    input = trim(input)
    if input ~= "" then
      on_submit(input)
    end
  end)
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function selection_text(buf, range)
  if range and range.line1 and range.line2 then
    local lines = vim.api.nvim_buf_get_lines(buf, range.line1 - 1, range.line2, false)
    return table.concat(lines, "\n"), { start_line = range.line1, end_line = range.line2 }
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil, nil
  end

  local srow, scol = start_pos[2] - 1, math.max(start_pos[3] - 1, 0)
  local erow, ecol = end_pos[2] - 1, math.max(end_pos[3], 1)
  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol - 1, scol + 1
  end

  local mode = vim.fn.visualmode()
  local lines
  if mode == "V" or mode == "\22" then
    lines = vim.api.nvim_buf_get_lines(buf, srow, erow + 1, false)
  else
    lines = vim.api.nvim_buf_get_text(buf, srow, scol, erow, ecol, {})
  end

  return table.concat(lines, "\n"), { start_line = srow + 1, end_line = erow + 1 }
end

local function current_patch_buf(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].codex_patch_root then
    return buf
  end
  notify("Current buffer is not a Codex patch buffer", vim.log.levels.WARN)
  return nil
end

local function patch_text(buf)
  return trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
end

local function patch_payload(text)
  text = trim(text)
  if text == "" then
    return ""
  end
  return text:match("\n$") and text or (text .. "\n")
end

local function normalize_patch(response)
  local text = trim(response)
  if text == "" or text == "NO_CHANGES" then
    return ""
  end

  local lines = vim.split(text, "\n", { plain = true })
  if #lines >= 2 and lines[1]:match("^```") then
    if lines[#lines] == "```" then
      table.remove(lines, #lines)
    end
    table.remove(lines, 1)
    text = trim(table.concat(lines, "\n"))
  end

  local markers = {
    "^diff %-%-git ",
    "^%-%-%- ",
  }

  local found_from = nil
  local scan = vim.split(text, "\n", { plain = true })
  for idx, line in ipairs(scan) do
    for _, marker in ipairs(markers) do
      if line:match(marker) then
        found_from = idx
        break
      end
    end
    if found_from then
      break
    end
  end

  if found_from and found_from > 1 then
    text = table.concat(vim.list_slice(scan, found_from), "\n")
  end

  return trim(text)
end

local function split_text(text)
  if text == "" then
    return {}
  end

  local lines = vim.split(text, "\n", { plain = true, trimempty = false })
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  return lines
end

local function read_file_text(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local stat = vim.uv.fs_fstat(fd)
  local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
  vim.uv.fs_close(fd)
  return data
end

local function write_file_text(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, text, 0))
  assert(vim.uv.fs_close(fd))
end

local function file_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file" or false
end

local function path_join(...)
  return table.concat({ ... }, "/"):gsub("//+", "/")
end

local function strip_prefix(path)
  if not path or path == "/dev/null" then
    return path
  end
  return path:gsub("^[ab]/", "", 1)
end

local function patch_targets(patch)
  local targets = {}
  for line in patch:gmatch("[^\r\n]+") do
    local old_path, new_path = line:match("^diff %-%-git a/(.+) b/(.+)$")
    if old_path and new_path then
      targets[#targets + 1] = {
        old_path = old_path,
        new_path = new_path,
      }
    end
  end

  return targets
end

local function load_project_file_text(root, rel_path)
  if not rel_path or rel_path == "/dev/null" then
    return ""
  end

  local abs_path = path_join(root, rel_path)
  local bufnr = vim.fn.bufnr(abs_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    if text ~= "" and vim.bo[bufnr].endofline then
      text = text .. "\n"
    end
    return text
  end

  return read_file_text(abs_path) or ""
end

-- Apply `patch` inside `cwd` and return (ok, stderr). Tries strict `git apply`
-- first; on failure, falls back to GNU `patch --fuzz=2`. Rejected hunks are
-- surfaced through stderr rather than silently dropped (the "25 changes but
-- only one landed" bug that happens with `-r -`).
local function apply_patch_lenient(cwd, patch_path)
  local git = vim
    .system({
      "git",
      "apply",
      "--recount",
      "--whitespace=nowarn",
      patch_path,
    }, { cwd = cwd, text = true })
    :wait()
  if git.code == 0 then
    return true, ""
  end

  if vim.fn.executable("patch") ~= 1 then
    return false, trim(git.stderr)
  end

  local gp = vim
    .system({
      "patch",
      "-p1",
      "--forward",
      "--fuzz=2",
      "--no-backup-if-mismatch",
      "-s",
      "-i",
      patch_path,
    }, { cwd = cwd, text = true })
    :wait()

  -- Look for .rej files inside cwd: a nonzero patch exit plus rejects means
  -- some hunks silently failed. Treat any rejects as failure.
  local rejects = vim.fs.find(function(name)
    return name:match("%.rej$")
  end, { path = cwd, type = "file", limit = 10 })

  if gp.code == 0 and vim.tbl_isempty(rejects) then
    return true, ""
  end

  local parts = { "git apply:", trim(git.stderr) }
  if gp.stderr and gp.stderr ~= "" then
    parts[#parts + 1] = ""
    parts[#parts + 1] = "patch --fuzz=2:"
    parts[#parts + 1] = trim(gp.stderr)
  end
  if not vim.tbl_isempty(rejects) then
    parts[#parts + 1] = ""
    parts[#parts + 1] = "Rejected hunks:"
    for _, rej in ipairs(rejects) do
      parts[#parts + 1] = "  " .. rej
    end
  end
  return false, table.concat(parts, "\n")
end

local function patch_preview_data(root, patch)
  patch = patch_payload(patch)
  local targets = patch_targets(patch)
  if #targets ~= 1 then
    return nil
  end

  local target = targets[1]
  local old_rel = strip_prefix(target.old_path)
  local new_rel = strip_prefix(target.new_path)
  local view_rel = new_rel ~= "/dev/null" and new_rel or old_rel
  if not view_rel or view_rel == "/dev/null" then
    return nil
  end

  local tmp_root = vim.fn.tempname()
  vim.fn.mkdir(tmp_root, "p")

  if old_rel and old_rel ~= "/dev/null" then
    write_file_text(path_join(tmp_root, old_rel), load_project_file_text(root, old_rel))
  end

  local patch_path = path_join(tmp_root, "codex-preview.patch")
  write_file_text(patch_path, patch)

  local ok, err = apply_patch_lenient(tmp_root, patch_path)
  if not ok then
    return nil, err
  end

  local proposed_path = path_join(tmp_root, view_rel)
  local original_text = load_project_file_text(root, old_rel ~= "/dev/null" and old_rel or view_rel)
  local proposed_text = file_exists(proposed_path) and (read_file_text(proposed_path) or "") or ""
  local filetype = vim.filetype.match({ filename = view_rel }) or ""

  return {
    path = view_rel,
    original_text = original_text,
    proposed_text = proposed_text,
    filetype = filetype,
  }
end

local function review_script_path()
  return path_join(vim.fn.stdpath("config"), "bin", "codex-patch-review")
end

local function review_win_opts(root, title)
  return {
    width = 0.9,
    height = 0.88,
    row = 0.05,
    col = 0.05,
    title = (" %s: %s "):format(title or "Codex Review", M.project_name(root)),
    title_pos = "center",
  }
end

local function open_patch_terminal(opts)
  local script = review_script_path()
  if vim.fn.executable(script) ~= 1 then
    return false
  end

  local patch = patch_payload(opts.patch)
  if patch == "" then
    return false
  end

  local patch_path = vim.fn.tempname() .. ".patch"
  write_file_text(patch_path, patch)

  Snacks.terminal.toggle({
    script,
    patch_path,
    opts.root,
    opts.title or "Codex Patch Review",
  }, {
    count = 6,
    cwd = opts.root,
    win = review_win_opts(opts.root, opts.title or "Codex Review"),
  })

  notify("Codex review opened in a terminal. Use ctrl-e to edit, ctrl-a to apply, or ctrl-d to discard.")
  return true
end

local function patch_request(prompt, sections)
  local lines = {
    "Return only a unified git diff patch relative to the project root.",
    "Do not include explanations, markdown fences, bullet points, or surrounding prose.",
    "Use enough context lines for `git apply --recount` to succeed.",
    "Prefer modifying existing files over rewriting unrelated code.",
    "If no changes are necessary, return exactly NO_CHANGES.",
    "",
    prompt,
  }

  if sections then
    for _, section in ipairs(sections) do
      lines[#lines + 1] = ""
      lines[#lines + 1] = section
    end
  end

  return table.concat(lines, "\n")
end

local function setup_patch_buffer(buf, opts)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, split_text(opts.patch))

  vim.b[buf].codex_patch_root = opts.root
  vim.b[buf].codex_patch_title = opts.title
  vim.b[buf].codex_patch_source = opts.source or ""
  vim.b[buf].codex_patch_tabpage = opts.tabpage or nil
  vim.b[buf].codex_patch_preview_path = opts.preview_path or ""
  vim.b[buf].codex_patch_preview_seq = opts.preview_seq or nil
  vim.b[buf].codex_patch_original_buf = opts.original_buf or nil
  vim.b[buf].codex_patch_proposed_buf = opts.proposed_buf or nil

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      require("utils.codex").accept_patch(buf)
    end,
  })

  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end

  map("<leader>aa", function()
    require("utils.codex").accept_patch(buf)
  end, "Accept Codex Patch")
  map("<leader>ad", function()
    require("utils.codex").deny_patch(buf)
  end, "Deny Codex Patch")
  map("<leader>ar", function()
    require("utils.codex").refresh_patch_preview(buf)
  end, "Refresh Codex Patch Preview")
  map("q", function()
    require("utils.codex").deny_patch(buf)
  end, "Close Codex Patch")
end

local function set_scratch_content(buf, name, filetype, text)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = filetype or ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, split_text(text))
  vim.bo[buf].modifiable = false
end

local function open_patch_buffer(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  patch_seq = patch_seq + 1
  local seq = patch_seq
  local name = PATCH_BUF_PREFIX .. M.project_name(opts.root) .. "#" .. seq
  vim.api.nvim_buf_set_name(buf, name)

  if opts.preview then
    vim.cmd("tabnew")
    local tabpage = vim.api.nvim_get_current_tabpage()

    local original_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(original_buf, "codex://preview/original/" .. opts.preview.path .. "#" .. seq)
    vim.bo[original_buf].bufhidden = "wipe"
    vim.bo[original_buf].swapfile = false
    vim.bo[original_buf].modifiable = true
    vim.bo[original_buf].filetype = opts.preview.filetype
    vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, split_text(opts.preview.original_text))
    vim.bo[original_buf].modifiable = false

    vim.api.nvim_win_set_buf(0, original_buf)
    vim.api.nvim_set_option_value("diff", true, { win = 0 })

    vim.cmd("vsplit")
    local proposed_win = vim.api.nvim_get_current_win()
    local proposed_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(proposed_buf, "codex://preview/proposed/" .. opts.preview.path .. "#" .. seq)
    vim.bo[proposed_buf].bufhidden = "wipe"
    vim.bo[proposed_buf].swapfile = false
    vim.bo[proposed_buf].modifiable = true
    vim.bo[proposed_buf].filetype = opts.preview.filetype
    vim.api.nvim_buf_set_lines(proposed_buf, 0, -1, false, split_text(opts.preview.proposed_text))
    vim.bo[proposed_buf].modifiable = false
    vim.api.nvim_win_set_buf(proposed_win, proposed_buf)
    vim.api.nvim_set_option_value("diff", true, { win = proposed_win })

    vim.cmd("botright split")
    local patch_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(patch_win, math.max(12, math.floor(vim.o.lines * 0.28)))
    vim.api.nvim_win_set_buf(patch_win, buf)
    vim.api.nvim_set_option_value("wrap", false, { win = patch_win })

    setup_patch_buffer(buf, {
      patch = opts.patch,
      root = opts.root,
      title = opts.title,
      source = opts.source,
      tabpage = tabpage,
      preview_path = opts.preview.path,
      preview_seq = seq,
      original_buf = original_buf,
      proposed_buf = proposed_buf,
    })

    notify(
      "Codex patch opened with side-by-side preview. Edit the patch below, use <leader>ar to refresh, then :w or <leader>aa to apply."
    )
    return buf
  end

  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, math.max(90, math.floor(vim.o.columns * 0.5)))
  vim.api.nvim_set_option_value("wrap", false, { win = win })

  setup_patch_buffer(buf, opts)
  notify("Codex patch opened. Edit it, then use :w or <leader>aa to apply. Use <leader>ad to discard.")
  return buf
end

local function finalize_patch_accept(buf, tabpage, title)
  notify(title .. " applied")
  vim.cmd("checktime")
  if tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
    pcall(vim.cmd, vim.api.nvim_tabpage_get_number(tabpage) .. "tabclose")
  elseif vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

-- Fuzz fallback: GNU patch tolerates drifted hunk offsets and edited context
-- that strict `git apply` rejects with "error: patch failed: FILE:NNN". The
-- dry-run guard ensures we never half-apply a patch: if any hunk would
-- reject, we stop and surface the failure so the user can fix the patch
-- buffer before retrying. Mirrors bin/codex-patch-review's apply_patch.
local function patch_fuzz_apply(buf, patch, root, title, tabpage, git_stderr)
  if vim.fn.executable("patch") ~= 1 then
    notify("Patch apply failed", vim.log.levels.ERROR)
    open_error_output(title .. " Apply Failed", git_stderr)
    return
  end

  local fuzz_args = function(dry_run)
    local args = { "patch", "-p1", "--forward", "--fuzz=2", "--no-backup-if-mismatch", "-s" }
    if dry_run then
      args[#args + 1] = "--dry-run"
    end
    return args
  end

  vim.system(fuzz_args(true), { stdin = patch, text = true, cwd = root }, function(dry)
    vim.schedule(function()
      if dry.code ~= 0 then
        notify("Patch would only apply partially; nothing changed", vim.log.levels.ERROR)
        local details = trim(dry.stderr ~= "" and dry.stderr or dry.stdout)
        if details == "" then
          details = git_stderr
        end
        open_error_output(title .. " Apply Rejected", details)
        return
      end

      vim.system(fuzz_args(false), { stdin = patch, text = true, cwd = root }, function(real)
        vim.schedule(function()
          if real.code ~= 0 then
            notify("Patch apply failed", vim.log.levels.ERROR)
            local details = trim(real.stderr)
            if details == "" then
              details = git_stderr
            end
            open_error_output(title .. " Apply Failed", details)
            return
          end
          finalize_patch_accept(buf, tabpage, title .. " (with fuzz)")
        end)
      end)
    end)
  end)
end

function M.accept_patch(buf)
  buf = current_patch_buf(buf)
  if not buf then
    return
  end

  local patch = patch_payload(patch_text(buf))
  if patch == "" then
    notify("Patch buffer is empty", vim.log.levels.WARN)
    return
  end

  local root = vim.b[buf].codex_patch_root
  local title = vim.b[buf].codex_patch_title or "Codex Patch"
  local tabpage = vim.b[buf].codex_patch_tabpage

  vim.system({
    "git",
    "apply",
    "--recount",
    "--whitespace=nowarn",
  }, {
    stdin = patch,
    text = true,
    cwd = root,
  }, function(apply)
    vim.schedule(function()
      if apply.code == 0 then
        finalize_patch_accept(buf, tabpage, title)
        return
      end
      patch_fuzz_apply(buf, patch, root, title, tabpage, trim(apply.stderr))
    end)
  end)
end

function M.deny_patch(buf)
  buf = current_patch_buf(buf)
  if not buf then
    return
  end

  local title = vim.b[buf].codex_patch_title or "Codex Patch"
  local tabpage = vim.b[buf].codex_patch_tabpage
  notify(title .. " discarded")
  if tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
    pcall(vim.cmd, vim.api.nvim_tabpage_get_number(tabpage) .. "tabclose")
    return
  end
  vim.api.nvim_buf_delete(buf, { force = true })
end

function M.refresh_patch_preview(buf)
  buf = current_patch_buf(buf)
  if not buf then
    return
  end

  local patch = patch_payload(patch_text(buf))
  if patch == "" then
    notify("Patch buffer is empty", vim.log.levels.WARN)
    return
  end

  local root = vim.b[buf].codex_patch_root
  local title = vim.b[buf].codex_patch_title or "Codex Patch"
  local preview, preview_err = patch_preview_data(root, patch)
  if preview_err and preview_err ~= "" then
    notify("Patch preview refresh failed", vim.log.levels.ERROR)
    open_error_output(title .. " Preview Refresh Failed", preview_err)
    return
  end

  if not preview then
    notify("Preview refresh only works for single-file patches", vim.log.levels.WARN)
    return
  end

  local original_buf = vim.b[buf].codex_patch_original_buf
  local proposed_buf = vim.b[buf].codex_patch_proposed_buf
  if
    not (
      original_buf
      and proposed_buf
      and vim.api.nvim_buf_is_valid(original_buf)
      and vim.api.nvim_buf_is_valid(proposed_buf)
    )
  then
    local current_win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(current_win)
    local patch_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local meta = {
      title = title,
      root = root,
      source = vim.b[buf].codex_patch_source or "",
      patch = patch,
      preview = preview,
    }
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    local new_buf = open_patch_buffer(meta)
    vim.schedule(function()
      if new_buf and vim.api.nvim_buf_is_valid(new_buf) then
        vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, patch_lines)
        pcall(vim.api.nvim_win_set_cursor, 0, cursor)
      end
    end)
    return
  end

  local seq = vim.b[buf].codex_patch_preview_seq or patch_seq
  local filetype = preview.filetype or ""
  set_scratch_content(
    original_buf,
    "codex://preview/original/" .. preview.path .. "#" .. seq,
    filetype,
    preview.original_text
  )
  set_scratch_content(
    proposed_buf,
    "codex://preview/proposed/" .. preview.path .. "#" .. seq,
    filetype,
    preview.proposed_text
  )
  vim.b[buf].codex_patch_preview_path = preview.path
  notify(title .. " preview refreshed")
end

local function run_patch(request, opts)
  run_exec_capture(request, opts, function(result)
    if result.code ~= 0 then
      open_error_output(result.title .. " Failed", result.stderr)
      notify(("%s failed with exit code %d"):format(result.title, result.code), vim.log.levels.ERROR)
      return
    end

    local patch = normalize_patch(result.response)
    if patch == "" then
      notify(result.title .. ": no changes proposed")
      return
    end

    local preview, preview_err = patch_preview_data(result.root, patch)
    if preview_err and preview_err ~= "" then
      notify("Patch preview could not be generated; opening raw patch buffer instead", vim.log.levels.WARN)
      open_error_output(result.title .. " Preview Warning", preview_err)
    end

    local opened = M.review_patch(patch, {
      title = result.title,
      root = result.root,
      source = result.source,
    })
    if opened then
      return
    end

    open_patch_buffer({
      title = result.title,
      root = result.root,
      source = result.source,
      patch = patch,
      preview = preview,
    })
  end)
end

function M.review_patch(patch, opts)
  opts = opts or {}
  patch = normalize_patch(patch or "")
  if patch == "" then
    notify("No patch to review", vim.log.levels.WARN)
    return false
  end

  local root = opts.root or M.project_root()
  if
    open_patch_terminal({
      title = opts.title or "Codex Patch Review",
      root = root,
      source = opts.source,
      patch = patch,
    })
  then
    return true
  end

  return false
end

function M.exec(args, opts)
  opts = opts or {}
  local function submit(prompt)
    run_exec(prompt, {
      title = "Codex Exec",
      workspace_write = opts.workspace_write,
      buf = opts.buf,
    })
  end

  args = trim(args)
  if args ~= "" then
    submit(args)
    return
  end

  ask_for_prompt("Codex exec prompt: ", submit)
end

function M.send_file(args, opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local root = M.project_root(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local source = relative_path(path, root)
  local filetype = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
  local content = truncate_context(buffer_text(buf))

  local function submit(prompt)
    local request = table.concat({
      prompt,
      "",
      ("Project root: %s"):format(root),
      ("File: %s"):format(source),
      "",
      ("```%s"):format(filetype),
      content,
      "```",
    }, "\n")

    run_exec(request, {
      title = "Codex Send File",
      workspace_write = opts.workspace_write,
      buf = buf,
      root = root,
      source = source,
    })
  end

  args = trim(args)
  if args ~= "" then
    submit(args)
    return
  end

  ask_for_prompt("Codex file prompt: ", submit)
end

function M.send_selection(args, opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local text, range = selection_text(buf, opts.range)
  if not text or text == "" then
    notify("No visual selection found", vim.log.levels.WARN)
    return
  end

  local root = M.project_root(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local source = relative_path(path, root)
  local filetype = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
  text = truncate_context(text)

  local function submit(prompt)
    local request = table.concat({
      prompt,
      "",
      ("Project root: %s"):format(root),
      ("File: %s"):format(source),
      ("Selected lines: %d-%d"):format(range.start_line, range.end_line),
      "",
      ("```%s"):format(filetype),
      text,
      "```",
    }, "\n")

    run_exec(request, {
      title = "Codex Send Selection",
      workspace_write = opts.workspace_write,
      buf = buf,
      root = root,
      source = source .. (range and (":%d-%d"):format(range.start_line, range.end_line) or ""),
    })
  end

  args = trim(args)
  if args ~= "" then
    submit(args)
    return
  end

  ask_for_prompt("Codex selection prompt: ", submit)
end

function M.patch(args, opts)
  opts = opts or {}

  local function submit(prompt)
    run_patch(
      patch_request(prompt, {
        ("Project root: %s"):format(M.project_root(opts.buf)),
      }),
      {
        title = "Codex Patch",
        buf = opts.buf,
      }
    )
  end

  args = trim(args)
  if args ~= "" then
    submit(args)
    return
  end

  ask_for_prompt("Codex patch prompt: ", submit)
end

function M.patch_file(args, opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local root = M.project_root(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local source = relative_path(path, root)
  local filetype = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
  local content = truncate_context(buffer_text(buf))

  local function submit(prompt)
    run_patch(
      patch_request(prompt, {
        ("Project root: %s"):format(root),
        ("Focus file: %s"):format(source),
        ("```%s"):format(filetype),
        content,
        "```",
      }),
      {
        title = "Codex Patch File",
        buf = buf,
        root = root,
        source = source,
      }
    )
  end

  args = trim(args)
  if args ~= "" then
    submit(args)
    return
  end

  ask_for_prompt("Codex patch file prompt: ", submit)
end

function M.patch_selection(args, opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local text, range = selection_text(buf, opts.range)
  if not text or text == "" then
    notify("No visual selection found", vim.log.levels.WARN)
    return
  end

  local root = M.project_root(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local source = relative_path(path, root)
  local filetype = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
  text = truncate_context(text)

  local function submit(prompt)
    run_patch(
      patch_request(prompt, {
        ("Project root: %s"):format(root),
        ("Focus file: %s"):format(source),
        ("Selected lines: %d-%d"):format(range.start_line, range.end_line),
        ("```%s"):format(filetype),
        text,
        "```",
      }),
      {
        title = "Codex Patch Selection",
        buf = buf,
        root = root,
        source = source .. (":%d-%d"):format(range.start_line, range.end_line),
      }
    )
  end

  args = trim(args)
  if args ~= "" then
    submit(args)
    return
  end

  ask_for_prompt("Codex patch selection prompt: ", submit)
end

return M
