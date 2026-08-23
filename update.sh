#!/usr/bin/env bash
# AutoVim updater.
#
# Usage:
#   ~/.config/nvim/update.sh
#   curl -fsSL https://raw.githubusercontent.com/yongjohnlee80/autovim/main/update.sh | bash
#
# Overrides (env vars):
#   AUTOVIM_BRANCH=<name>           track a non-default branch (forks / testing)
#   AUTOVIM_REPO=<url>              fork URL (default: upstream)
#   AUTOVIM_UPDATE_REEXEC=1         internal: set on the self-handoff, so the
#                                   successor knows not to hand off again
#   AUTOVIM_NO_LAZY_SYNC=1          skip the post-update `Lazy! sync`
#   AUTOVIM_NO_FAMILY_UPDATE=1      skip the `Lazy update <family>` step
#   AUTOVIM_FAMILY_PLUGINS="a b"    space-separated override of the family list
#
# How it works:
#   1. Hard-reset $NVIM_CONFIG/.git to origin/<branch>. This advances
#      the local branch ref AND replaces every tracked file in the
#      working tree with origin's version. Skipped when `.git/` is
#      missing. Gitignored paths (lua/custom/, lazy-lock backups,
#      .auto-agents-config, …) are NOT touched — that's the user's
#      customization surface and stays intact across updates.
#   2. Clone origin/<branch> at depth 1 into a temp dir and `rsync -a
#      --exclude='.git/'` it onto $NVIM_CONFIG. For installs WITH .git/
#      this overlays the same bytes the hard reset already produced
#      (no-op for tracked files). For installs WITHOUT .git/ — raw
#      tarball drops, edge cases — the rsync IS the update mechanism.
#   3. Run `nvim --headless +Lazy! sync` so the refreshed
#      lazy-lock.json pulls the pinned plugin versions; then
#      `Lazy! update <family>` so caret pins advance.
#
# **Fork users:** the hard reset uses the LOCAL `.git/`'s `origin`
# remote (whatever URL it points at), not $AUTOVIM_REPO. Point your
# `.git/`'s origin at your fork (`git remote set-url origin <fork>`)
# and update.sh will track your fork's branch. If your fork carries
# committed-on-top changes against upstream, the hard reset will move
# them to your fork's origin/<branch> tip — commit your work through
# the fork's remote before invoking update.sh.
#
# rsync replaces an earlier `git archive HEAD | tar -x` pipeline. macOS
# ships bsdtar (libarchive), which trips on `git archive`'s pax global
# header and bails with "`.`: Can't replace existing directory with
# non-directory". GNU tar (Linux) silently handles the same header, so
# the bug only surfaced on macOS. rsync sidesteps the tar format
# entirely and behaves identically across both platforms.

set -euo pipefail

REPO="${AUTOVIM_REPO:-https://github.com/yongjohnlee80/autovim.git}"
# This script updates ITSELF. `detect_branch` and every other decision below is
# evaluated by the copy already on disk, so a run can only ever fetch the new
# update.sh — the new logic does not take effect until the NEXT invocation. That
# is why upgrades historically needed two runs. `maybe_selfupdate` closes it:
# it fetches the newest update.sh FIRST and hands off before any decision.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum  >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else echo "unhashable"; fi
}
SELF_HASH="$([[ -f "$SELF" ]] && hash_of "$SELF" || echo unknown)"
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# AutoVim-authored plugins. After overlaying the new lazy-lock.json
# we run `Lazy update` on these explicitly so caret pins
# (`version = "^0.X.0"`) advance to the newest tag inside that line —
# `Lazy sync` alone would re-pin to upstream's committed lock without
# checking the remote for a newer matching tag.
FAMILY_PLUGINS_DEFAULT=(
  "auto-core.nvim"
  "auto-agents"
  "auto-finder.nvim"
  "auto-run.nvim"
  "md-harpoon.nvim"
  "worktree.nvim"
  "remote-sync.nvim"
)

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; exit 1; }

# AutoVim is a SINGLE branch now. `mac-os` and `omarchy` were retired once
# every OS-specific behaviour moved onto `main` behind a runtime check in
# `lua/utils/platform.lua` — macOS still gets its Mason-free gopls, Omarchy
# still follows the system theme, both from the same commit.
#
# This is the migration path for the installs that are still ON one of those
# branches. We deliberately do NOT trust the local checkout's current branch
# any more (the previous version did): trusting it is exactly what would pin an
# existing Omarchy or macOS user to a branch that no longer receives commits.
# `AUTOVIM_BRANCH` remains the escape hatch for forks.
LEGACY_BRANCHES=("mac-os" "omarchy")

detect_branch() {
  echo "${AUTOVIM_BRANCH:-main}"
}

# The branch the local checkout is on right now, or empty when there is no
# tracked `.git/` (rsync-overlay installs).
current_local_branch() {
  [[ -d "$NVIM_CONFIG/.git" ]] || return 0
  git -C "$NVIM_CONFIG" rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

is_legacy_branch() {
  local candidate="$1" legacy
  for legacy in "${LEGACY_BRANCHES[@]}"; do
    [[ "$candidate" == "$legacy" ]] && return 0
  done
  return 1
}

# Tell the user what is about to happen to their branch, loudly. Silently
# moving someone off the branch they installed is the kind of surprise that
# reads as a broken update.
announce_branch_migration() {
  local from="$1" to="$2"
  warn "This install tracks the retired '$from' branch; migrating it to '$to'."
  warn "  Every '$from' behaviour now lives on '$to' and is selected at runtime."
  warn "  Your gitignored files (lua/custom/, .auto-agents-config/, ...) are untouched."
}

# Idempotent sanity-check that mirrors install.sh's `scaffold_custom`.
# Older AutoVim installs (pre-`scaffold_custom`, before mid-2026) never
# created `lua/custom/` and now have no place for user overrides. Re-runs
# of this script copy `docs/custom-example/` over only if `lua/custom/`
# is still missing — never clobbers an existing custom layer.
scaffold_custom_if_missing() {
  local target="$NVIM_CONFIG/lua/custom"
  local source="$NVIM_CONFIG/docs/custom-example"
  if [[ -d "$target" ]]; then
    return
  fi
  if [[ ! -d "$source" ]]; then
    warn "docs/custom-example missing — skipping custom-layer scaffold (older AutoVim checkout?)"
    return
  fi
  log "Scaffolding user custom layer (first-time on this install): $target"
  cp -r "$source" "$target"
}

# One-shot v0.3.10 migration: lazysql was retired as a stock plugin and
# the snacks-terminal `<C-q>` binding moved with it. If the pre-overlay
# install had the stock `lua/plugins/lazysql.lua` spec, seed an equivalent
# spec into the user's custom layer so `<C-q>` keeps working until they
# choose to drop it. The seeded file lives in `lua/custom/plugins/` —
# user-owned territory; AutoVim will never overwrite it on future
# updates. Skipped if the user already has a file at that path (manual
# edits respected).
#
# Trigger condition is captured *before* `overlay_tracked_tree` runs:
# the new overlay no longer ships `lua/plugins/lazysql.lua`, so checking
# after-the-fact would never detect the upgrade.
PRE_UPGRADE_HAD_LAZYSQL=0
detect_pre_upgrade_lazysql() {
  if [[ -f "$NVIM_CONFIG/lua/plugins/lazysql.lua" ]]; then
    PRE_UPGRADE_HAD_LAZYSQL=1
  fi
}

migrate_lazysql_to_custom() {
  if [[ "$PRE_UPGRADE_HAD_LAZYSQL" != "1" ]]; then
    return
  fi
  local target="$NVIM_CONFIG/lua/custom/plugins/lazysql.lua"
  if [[ -f "$target" ]]; then
    log "v0.3.10 migration: lua/custom/plugins/lazysql.lua already present — leaving it alone"
    return
  fi
  if [[ ! -d "$NVIM_CONFIG/lua/custom/plugins" ]]; then
    # scaffold_custom_if_missing should have created this; if it didn't
    # (docs/custom-example missing), bail rather than `mkdir -p` an
    # orphaned dir the user didn't sign up for.
    warn "v0.3.10 migration: lua/custom/plugins/ missing — skipping lazysql seed. Re-run after manually creating lua/custom/."
    return
  fi
  log "v0.3.10 migration: seeding $target so <C-q> keeps working until you migrate to autodb"
  cat > "$target" <<'LAZYSQL_LUA'
-- DEPRECATED — preserved by AutoVim's v0.3.10 update.sh migration.
--
-- AutoVim retired the stock lazysql float in v0.3.10. The replacement is
-- autodb (`<leader>D*`, and the auto-finder `dbase` section) as of v0.4.0 —
-- nvim-dbee, which briefly held that role, is fully deprecated and no longer
-- installed. This file keeps the old `<C-q>` lazysql float available for users
-- who haven't migrated yet — but it lives in your user-owned `lua/custom/`
-- layer now: AutoVim will never overwrite it on `update.sh`, and you own its
-- lifecycle from here. Delete the file once you're comfortable with autodb.
--
-- Note: this spec assumes the `lazysql` binary is on PATH. AutoVim no
-- longer `go install`s it for you in v0.3.10+; install manually with:
--
--   go install github.com/jorgerojas26/lazysql@latest

return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<C-q>",
        function()
          Snacks.terminal.toggle("lazysql", {
            win = { style = "lazygit" },
          })
        end,
        mode = { "n", "t" },
        desc = "LazySQL (deprecated; see autodb, <leader>Dc)",
      },
    },
  },
}
LAZYSQL_LUA
}

# Bring the local checkout's branch ref in line with origin so the
# rsync below isn't laying new files on top of a stale `.git/` HEAD.
# This step is deliberately destructive against uncommitted edits to
# tracked files and against local commits: AutoVim's customization
# contract puts user-owned changes in `lua/custom/` (gitignored), so a
# hard reset of tracked content is the simplest "make it match origin"
# operation. Forks that want different semantics should set
# AUTOVIM_REPO=<fork-url> and commit through that fork's origin.
#
# Skipped silently when `.git/` is missing — the rsync overlay below
# handles that case as the sole update mechanism.
hard_reset_to_origin() {
  local target_branch="$1"
  if [[ ! -d "$NVIM_CONFIG/.git" ]]; then
    log "No .git/ in $NVIM_CONFIG — skipping hard reset; rsync will handle the overlay"
    return
  fi
  local local_branch
  local_branch="$(current_local_branch)"

  # `--tags` so the checkout carries the version tags. Without them
  # `git describe --tags` in ~/.config/nvim reported a description based on
  # whatever old tag it happened to have (v0.3.25-…) even though the CONTENT
  # was current — so "what version am I on?" answered wrong.
  # Three ways to reach the new tree, in order, because only the FIRST needs
  # the configured remote to be usable.
  #
  # `origin` is commonly an SSH URL, and a second machine may have no key
  # registered for it — while `$REPO` (the HTTPS upstream that
  # `overlay_tracked_tree` already clones from, moments later) works fine with
  # no credentials at all. Dying on the SSH failure stranded an update that had
  # a perfectly good path available, which is what a real report looked like.
  #
  # If neither reaches the network we do NOT die: the rsync overlay below is a
  # complete update mechanism on its own — it is exactly what runs for a
  # checkout with no `.git/` at all. The local branch ref stays where it was,
  # which is worth a loud warning but not a dead end.
  local ref="" fetch_err=""
  log "Fetching origin/$target_branch (with tags)"
  if fetch_err="$(git -C "$NVIM_CONFIG" fetch --tags origin "$target_branch" 2>&1)"; then
    ref="origin/$target_branch"
  else
    warn "git fetch origin $target_branch failed in $NVIM_CONFIG:"
    printf '%s\n' "$fetch_err" | sed 's/^/    /' >&2
    warn "Falling back to $REPO"
    if fetch_err="$(git -C "$NVIM_CONFIG" fetch --tags "$REPO" "$target_branch" 2>&1)"; then
      ref="FETCH_HEAD"
      log "Fetched from $REPO instead of origin."
      warn "Your 'origin' remote is unusable on this machine. To fix it permanently:"
      warn "    git -C $NVIM_CONFIG remote set-url origin $REPO"
    else
      warn "Fallback fetch from $REPO also failed:"
      printf '%s\n' "$fetch_err" | sed 's/^/    /' >&2
      warn "Skipping the git reset — the file overlay below will still update"
      warn "  your tracked files. Your branch ref stays at its current commit,"
      warn "  so re-run update.sh once the network or remote is usable."
      return 0
    fi
  fi

  # `checkout -f -B` in ONE step: create-or-reset the local branch to the
  # fetched tip AND move HEAD onto it. A bare `reset --hard origin/main` while
  # HEAD sits on `omarchy` would repoint the *omarchy* ref at main's content and
  # leave the user on a branch name that no longer exists upstream — the update
  # would look like it worked while still tracking a dead branch on the next run.
  #
  # `-f` discards local modifications to TRACKED files, which is AutoVim's
  # documented contract (user-owned changes belong in the gitignored
  # `lua/custom/`). Forks wanting other semantics set AUTOVIM_REPO.
  log "Checking out $target_branch at $ref"
  git -C "$NVIM_CONFIG" checkout -f -B "$target_branch" "$ref" --quiet \
    || die "git checkout -B $target_branch $ref failed in $NVIM_CONFIG"
}

overlay_tracked_tree() {
  local branch="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  log "Fetching AutoVim ($branch branch) into a temp dir"
  git clone --quiet --depth=1 --branch "$branch" "$REPO" "$tmpdir/autovim"

  log "Overlaying tracked files onto $NVIM_CONFIG (preserving lua/custom/ and every other gitignored path)"
  # The depth-1 clone is itself a faithful snapshot of the tracked tree:
  # no untracked, no gitignored files exist in a fresh clone. So rsync
  # from "$tmpdir/autovim/" while excluding `.git/` delivers exactly the
  # committed tree onto the user dir — same effect as a `git archive`
  # extraction, but without the bsdtar-vs-GNU-tar incompatibility on
  # `git archive`'s pax global header (which crashed macOS extracts).
  command -v rsync >/dev/null \
    || die "rsync not found on PATH — install it (apt/pacman/dnf/brew install rsync) and re-run."
  rsync -a --exclude='.git/' "$tmpdir/autovim/" "$NVIM_CONFIG/"
}

# Fetch the newest update.sh and hand off to it BEFORE doing any work.
#
# Every decision in this script — which branch to track, how to reset, what to
# overlay — is made by the copy already on disk. Handing off only AFTER the
# overlay (what v0.4.3 did) meant the OLD logic still chose the branch and did
# the reset, and the new script only got to run the tail end. Migrating off a
# retired branch therefore still needed a second invocation to be driven
# entirely by current logic.
#
# So: fetch just this one file from origin first, compare, and exec it. The new
# script then makes every decision, including the branch resolution.
#
# `git archive` is used rather than a clone: one file, no working tree, no
# temp checkout. Falls through silently on any failure — a self-update that
# cannot reach the network must not block an update that only needs the local
# overlay.
#
# The guard env var is what terminates this: the successor sees it set and skips
# the check, so at most one handoff happens per invocation.
# Repair a clone that v0.4.5/v0.4.6's `--depth=1` self-update turned shallow.
#
# Those versions fetched with `--depth=1`, which writes `.git/shallow` and
# truncates history. Anything inheriting that state keeps failing until it is
# undone, and the user cannot be expected to know that is what happened — so
# undo it here, before the fetch that would otherwise fail.
unshallow_if_needed() {
  [[ -d "$NVIM_CONFIG/.git" ]] || return 0
  [[ "$(git -C "$NVIM_CONFIG" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]] || return 0
  warn "This checkout is SHALLOW — an earlier AutoVim self-update (v0.4.5/v0.4.6)"
  warn "  fetched with --depth=1, which truncates history. Restoring full history."
  if git -C "$NVIM_CONFIG" fetch --quiet --unshallow origin 2>/dev/null; then
    log "History restored."
  else
    warn "Could not unshallow automatically. Run this by hand, then re-run update.sh:"
    warn "    git -C \"$NVIM_CONFIG\" fetch --unshallow origin"
  fi
}

maybe_selfupdate() {
  if [[ -n "${AUTOVIM_UPDATE_REEXEC:-}" ]]; then
    return 0
  fi
  [[ "$SELF_HASH" != "unknown" && "$SELF_HASH" != "unhashable" ]] || return 0

  local branch="$1" tmp
  tmp="$(mktemp)" || return 0
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  # NO --depth=1 here. It looked like a harmless optimisation for fetching one
  # file, but `git fetch --depth=1` CONVERTS A FULL CLONE INTO A SHALLOW ONE
  # (it writes .git/shallow). On a machine whose objects were all present it is
  # a no-op, which is why it passed here; on a machine that is behind it really
  # does truncate history, and a shallow clone then fails later operations
  # against a real remote. Shipped in v0.4.5 and reported from a second Omarchy
  # box as "git fetch origin main failed". A plain fetch costs a little more
  # traffic and cannot damage the checkout.
  # Same fallback as hard_reset_to_origin: origin may be an unusable SSH URL
  # on this machine while $REPO needs no credentials. A self-update that cannot
  # reach either simply does not happen — never fatal.
  if ! git -C "$NVIM_CONFIG" fetch --quiet origin "$branch" 2>/dev/null; then
    git -C "$NVIM_CONFIG" fetch --quiet "$REPO" "$branch" 2>/dev/null || return 0
  fi
  if ! git -C "$NVIM_CONFIG" show "FETCH_HEAD:update.sh" > "$tmp" 2>/dev/null; then
    return 0
  fi
  [[ -s "$tmp" ]] || return 0
  bash -n "$tmp" 2>/dev/null || return 0        # never exec a broken script

  local new_hash
  new_hash="$(hash_of "$tmp")"
  [[ "$new_hash" != "$SELF_HASH" ]] || return 0

  log "A newer update.sh is available — running that one instead"
  log "  (so the new logic drives the whole update, not just the tail)"
  install -m 0755 "$tmp" "$NVIM_CONFIG/update.sh" 2>/dev/null || return 0
  AUTOVIM_UPDATE_REEXEC=1 exec bash "$NVIM_CONFIG/update.sh" "$@"
}

install_autovim_cli() {
  local src="$NVIM_CONFIG/autovim.sh"
  local bindir="$HOME/.local/bin"
  local link="$bindir/autovim"
  if [[ ! -f "$src" ]]; then
    warn "autovim.sh not present in $NVIM_CONFIG — skipping CLI install"
    return
  fi
  mkdir -p "$bindir"
  chmod +x "$src"
  ln -sf "$src" "$link"
  log "Refreshed autovim CLI symlink: $link → $src"

  case ":$PATH:" in
    *":$bindir:"*) ;;
    *) warn "$bindir is not on PATH — add this to your shell rc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
}

run_lazy_sync() {
  if [[ "${AUTOVIM_NO_LAZY_SYNC:-0}" == "1" ]]; then
    log "AUTOVIM_NO_LAZY_SYNC=1 — skipping plugin sync"
    return
  fi
  if ! command -v nvim >/dev/null; then
    warn "nvim not on PATH — skipping Lazy sync. Open nvim manually; the bumped lazy-lock.json will install on first launch."
    return
  fi
  log "Running 'Lazy! sync' so plugin versions catch up with the new lockfile"
  nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "Lazy sync exited non-zero — finish interactively on next nvim launch."
}

run_lazy_update_family() {
  if [[ "${AUTOVIM_NO_FAMILY_UPDATE:-0}" == "1" ]]; then
    log "AUTOVIM_NO_FAMILY_UPDATE=1 — skipping AutoVim-family Lazy update"
    return
  fi
  if ! command -v nvim >/dev/null; then
    # Already warned above; don't double-warn.
    return
  fi
  local plugins
  if [[ -n "${AUTOVIM_FAMILY_PLUGINS:-}" ]]; then
    plugins="$AUTOVIM_FAMILY_PLUGINS"
  else
    plugins="${FAMILY_PLUGINS_DEFAULT[*]}"
  fi
  log "Advancing AutoVim-authored plugins to the newest tag in their caret line ('Lazy! update $plugins')"
  # `Lazy! update <names>` re-resolves each plugin's `version =`
  # constraint against its remote and writes the newer pin into
  # lazy-lock.json. After this step the local lock diverges from the
  # upstream lock for these plugins — that's the intended outcome.
  nvim --headless "+Lazy! update $plugins" +qa 2>/dev/null \
    || warn "Lazy update exited non-zero — finish interactively on next nvim launch."
}

report_status() {
  if [[ ! -d "$NVIM_CONFIG/.git" ]]; then
    return
  fi
  if ! git -C "$NVIM_CONFIG" rev-parse --git-dir >/dev/null 2>&1; then
    return
  fi
  local dirty
  dirty="$(git -C "$NVIM_CONFIG" status --porcelain | head -1)"
  if [[ -n "$dirty" ]]; then
    cat >&2 <<EOF

Your ~/.config/nvim/.git tree has pending changes after the overlay.
This is unexpected after the hard-reset step ran — most likely an
untracked file appeared during the run (e.g. a freshly-generated
lazy-lock backup). Inspect with:

  cd "$NVIM_CONFIG"
  git status

EOF
  fi
}

main() {
  local branch
  branch="${AUTOVIM_BRANCH:-$(detect_branch)}"

  log "AutoVim updater"
  log "  Target: $NVIM_CONFIG"
  log "  Branch: $branch"
  log "  Source: $REPO"

  if [[ ! -d "$NVIM_CONFIG" ]]; then
    die "No AutoVim install found at $NVIM_CONFIG — run install.sh first."
  fi

  # Before anything else: if origin has a newer update.sh, run THAT one.
  unshallow_if_needed
  maybe_selfupdate "$branch" "$@"

  # Capture pre-overlay markers BEFORE rsync replaces the tracked tree.
  detect_pre_upgrade_lazysql

  hard_reset_to_origin "$branch"
  overlay_tracked_tree "$branch"
  scaffold_custom_if_missing
  migrate_lazysql_to_custom
  install_autovim_cli
  run_lazy_sync
  run_lazy_update_family
  report_status

  cat >&2 <<EOF

AutoVim updated.

Tracked files were hard-reset to origin/<branch>. Gitignored paths
(lua/custom/, lazy-lock backups, .auto-agents-config, etc.) are
untouched. Restart nvim or run :Lazy reload to pick up new code.

Re-run with different options:
  AUTOVIM_BRANCH=<name>             Force a branch (main | mac-os | omarchy)
  AUTOVIM_REPO=<url>                Pull from a fork (also point your local origin at it)
  AUTOVIM_NO_LAZY_SYNC=1            Skip Lazy! sync
  AUTOVIM_NO_FAMILY_UPDATE=1        Skip Lazy update of AutoVim-authored plugins
  AUTOVIM_FAMILY_PLUGINS="a b c"    Override which plugins get the Lazy update

EOF
}

main "$@"
