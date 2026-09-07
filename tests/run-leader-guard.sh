#!/usr/bin/env bash
# tests/run-leader-guard.sh — sandbox + pinned-source runner for
# tests/leader-guard.lua (the family runner contract's sentinel gate).
#
# Why a dedicated runner: the suite must run against the STOCK pinned
# which-key revision recorded in lazy-lock.json (3aab2147…, parsed below —
# no hardcode drift) inside a fully sandboxed XDG environment, without
# touching the developer's live config, plugin cache, or any sibling
# worktree (tests-never-touch-the-developer-environment).
#
# Steps:
#   1. create the sandbox tempdir; set all four XDG roots + NVIM_LOG_FILE
#   2. read the which-key pin out of lazy-lock.json (single source of truth)
#   3. clone the stock repo from the local filesystem checkout when
#      available, else from GitHub; checkout the pinned commit
#   4. run the suite via `nvim --headless -u NONE -l`, gate on the summary
#      sentinel, propagate the exit code
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

repo_root="$PWD"
suite="tests/leader-guard.lua"

pin_json="$(grep -o '"which-key.nvim": { "branch": "[^"]*", "commit": "[^"]*"' lazy-lock.json)"
pin_commit="$(printf '%s' "$pin_json" | grep -oE 'commit": "[a-f0-9]+' | grep -oE '[a-f0-9]{7,}$')"
if [ -z "$pin_commit" ]; then
  echo "run-leader-guard: could not parse which-key pin from lazy-lock.json" >&2
  exit 1
fi

sandbox="$(mktemp -d /tmp/autovim-leader-guard.XXXXXX)"
mkdir -p "$sandbox"/{config,data,state,cache}
export AUTOTVIM_TEST_SANDBOX="$sandbox"
export AUTOTVIM_WK_SOURCE="$sandbox/which-key.nvim"
export XDG_CONFIG_HOME="$sandbox/config"
export XDG_DATA_HOME="$sandbox/data"
export XDG_STATE_HOME="$sandbox/state"
export XDG_CACHE_HOME="$sandbox/cache"
export NVIM_LOG_FILE="$sandbox/nvim.log"
unset NVIM NVIM_LISTEN_ADDRESS

local_checkout="/home/johno/Source/Projects/nvim-plugins/which-key.nvim/main"
if [ -d "$local_checkout/.git" ]; then
  git clone --quiet --no-hardlinks "$local_checkout" "$AUTOTVIM_WK_SOURCE"
else
  # Full clone (NOT --depth 1): the pinned commit is an older revision,
  # unreachable from a shallow HEAD tip.
  git clone --quiet https://github.com/folke/which-key.nvim.git "$AUTOTVIM_WK_SOURCE"
fi
git -C "$AUTOTVIM_WK_SOURCE" checkout --quiet --detach "$pin_commit"

printf 'sandbox: %s\nwhich-key pin: %s\n' "$sandbox" "$pin_commit"

out="$(nvim --headless -u NONE -l "$suite" 2>&1)" || rc=$?
rc=${rc:-0}
printf '%s\n' "$out"

summary="$(printf '%s\n' "$out" | grep -oE "[0-9]+ passed, [0-9]+ failed" | tail -1 || true)"
if [ -z "$summary" ]; then
  echo "run-leader-guard: NO SUMMARY — suite aborted mid-run" >&2
  exit 1
fi
echo "run-leader-guard: $summary (exit=$rc)"
if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi
exit 0