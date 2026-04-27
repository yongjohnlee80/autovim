-- remote-sync.nvim — keymap spec.
--
-- Plugin source: github.com/yongjohnlee80/remote-sync.nvim. Local working
-- copy lives at ~/Source/Projects/nvim-plugins/remote-sync.nvim for
-- development. To work against the local copy temporarily, add
-- `dir = vim.fn.expand("~/Source/Projects/nvim-plugins/remote-sync.nvim")`
-- next to the spec line below — lazy will use it instead of fetching.
--
-- The plugin auto-registers `:RemoteSync*` user commands; this spec only
-- adds the keymaps. See the plugin README for the workflow and the
-- `.autovim-remote.json` schema.
--
-- Without an `.autovim-remote.json` somewhere in or above cwd, every keymap
-- notifies and no-ops — safe to mash anywhere.

local function call(fn)
  return function() require("remote-sync")[fn]() end
end

return {
  {
    "yongjohnlee80/remote-sync.nvim",
    tag = "v0.1.0",
    lazy = true,
    keys = {
      -- Pull remote → local mirror, then auto-`git commit` the result as
      -- a snapshot baseline (only if the dir is a git repo). The committed
      -- HEAD is what the next drift check compares against.
      { "<leader>rp", call("pull"), desc = "Remote: pull (rsync + auto-snap commit)" },

      -- Drift check (read-only). Compares the remote against HEAD via a
      -- `git archive HEAD | tar -x` materialization + dry-run rsync.
      -- Empty output = no drift, output = remote moved under us.
      { "<leader>rd", call("drift"), desc = "Remote: drift report (no writes)" },

      -- Push local → remote. Drift-gated (compares remote to HEAD, NOT to
      -- working tree — so unpushed local edits don't count). Auto-commits
      -- a pre-push snapshot, then auto-pulls (quietly) post-push to catch
      -- any concurrent-writer state.
      { "<leader>rs", call("push"), desc = "Remote: push (refuses on remote drift; auto-snap before, auto-pull after)" },

      -- Force-push — bypasses the drift gate. Confirms via vim.ui.select
      -- to discourage habitual use; the gate exists for a reason.
      { "<leader>rS", function()
          vim.ui.select(
            { "no, cancel", "yes, force push" },
            { prompt = "Force push? Drift gate will be skipped — you may overwrite remote changes." },
            function(choice)
              if choice == "yes, force push" then
                require("remote-sync").push({ force = true })
              else
                vim.notify("[remote-sync] force push cancelled", vim.log.levels.INFO)
              end
            end
          )
        end,
        desc = "Remote: FORCE push (skip drift gate; confirms first)" },

      -- Run a project-configured remote command (`commands` array in
      -- the JSON) over ssh. Typically a service reload after pushing
      -- config changes. Notifies + no-ops if no commands are configured.
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
