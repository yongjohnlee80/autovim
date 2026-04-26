-- Remote-sync keymaps. The actual workflow — pull / drift / push / remote-cmd
-- / log — lives in `lua/utils/remote_sync.lua`. This spec is keymap-only;
-- there's no external plugin to install. Logic loads lazily on first keypress.
--
-- The full workflow and motivation are documented in
-- docs/design-decisions/2026-04-25-remote-dev-local-first-git-backed-sync.md.
-- Quick reference: drop a `.autovim-remote.json` in any directory that's
-- the root of a service mirror, e.g.:
--
--   { "host": "user@vps.team",
--     "remote_path": "/srv/mailcow/data/conf",
--     "exclude": [".git", "data", "logs"],
--     "delete": true,
--     "command": "docker compose restart postfix-mailcow" }
--
-- Without that file, every keymap notifies and no-ops — safe to mash anywhere.

local function call(fn)
  return function() require("utils.remote_sync")[fn]() end
end

return {
  {
    "remote-sync",
    dir = vim.fn.stdpath("config"),
    name = "remote-sync",
    lazy = true,
    keys = {
      -- Pull remote → local mirror, then auto-`git commit` the result as
      -- a snapshot baseline (only if the dir is a git repo). The committed
      -- HEAD is what the next drift check compares against.
      { "<leader>rp", call("pull"), desc = "Remote: pull (rsync + auto-snap commit)" },

      -- Drift check (read-only). Runs `rsync -azni --checksum --dry-run`;
      -- empty output = no drift, output = remote has changes since last
      -- pull. Cheap to run before deciding whether to push.
      { "<leader>rd", call("drift"), desc = "Remote: drift report (no writes)" },

      -- Push local → remote. Runs the drift check first (compares remote
      -- to HEAD, NOT to working tree — so unpushed local edits don't
      -- count as drift). Refuses if remote has changed since our last
      -- sync; the right next move is <leader>rp to pull-merge, then retry.
      -- Auto-commits a pre-push snapshot so HEAD always reflects what
      -- was last sent, then auto-pulls (quietly) post-push to catch any
      -- concurrent-writer state.
      { "<leader>rs", call("push"), desc = "Remote: push (refuses on remote drift; auto-snap before, auto-pull after)" },

      -- Force-push — bypasses the drift gate. Confirms via vim.ui.select
      -- to discourage habitual use; the gate exists for a reason.
      { "<leader>rS", function()
          vim.ui.select(
            { "no, cancel", "yes, force push" },
            { prompt = "Force push? Drift gate will be skipped — you may overwrite remote changes." },
            function(choice)
              if choice == "yes, force push" then
                require("utils.remote_sync").push({ force = true })
              else
                vim.notify("[remote-sync] force push cancelled", vim.log.levels.INFO)
              end
            end
          )
        end,
        desc = "Remote: FORCE push (skip drift gate; confirms first)" },

      -- Run the project-configured remote command (`config.command` in
      -- the JSON) over ssh. Typically a service reload after pushing
      -- config changes (e.g. `docker compose restart <svc>`). No-ops with
      -- a notify if no command is configured.
      { "<leader>rc", call("run_remote_cmd"), desc = "Remote: run configured command" },

      -- Show the last sync's full output in a floating window. q / <Esc>
      -- to close.
      { "<leader>rl", call("show_log"), desc = "Remote: show last sync log" },

      -- Register a new project — wizard for host / remote_path / dest_path.
      -- Creates the dir and a default .autovim-remote.json. Doesn't pull;
      -- :cd into the new dir + <leader>rp afterward.
      { "<leader>rR", call("register"), desc = "Remote: register new project (wizard)" },

      -- Project navigation. Mirrors worktree.nvim's <leader>gw / <leader>gW
      -- pattern within our own keyspace (intentionally not reusing gW so
      -- worktree's back-nav stays untouched). Discovery scans for
      -- .autovim-remote.json under ~/Source/Remote (or fallbacks); the cwd
      -- before each gq is pushed onto an in-memory stack so gQ pops back.
      { "<leader>gq", call("navigate"),      desc = "Remote: pick & cd to project" },
      { "<leader>gQ", call("navigate_back"), desc = "Remote: cd back from remote project" },
    },
  },
}
