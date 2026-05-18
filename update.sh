#!/usr/bin/env bash
# AutoVim updater.
#
# Usage:
#   ~/.config/nvim/update.sh
#   curl -fsSL https://raw.githubusercontent.com/yongjohnlee80/autovim/main/update.sh | bash
#
# Overrides (env vars):
#   AUTOVIM_BRANCH=<name>           force a specific branch (main | mac-os | omarchy)
#   AUTOVIM_REPO=<url>              fork URL (default: upstream)
#   AUTOVIM_NO_LAZY_SYNC=1          skip the post-update `Lazy! sync`
#   AUTOVIM_NO_FAMILY_UPDATE=1      skip the `Lazy update <family>` step
#   AUTOVIM_FAMILY_PLUGINS="a b"    space-separated override of the family list
#
# How it works:
#   1. Clone the latest AutoVim into a temp dir.
#   2. Overlay its tracked files into ~/.config/nvim using
#      `rsync -a --exclude='.git/'` from the depth-1 clone's working
#      tree. A fresh `git clone --depth=1` contains only tracked files
#      plus `.git/`, so excluding `.git/` is equivalent to "tracked
#      files only". This naturally:
#        * skips `.git/` (so the user's own git config — including a
#          fork remote, or no .git/ at all — survives the update),
#        * skips `lua/custom/` (never created in the temp clone →
#          rsync has nothing to copy → user customizations untouched),
#        * skips every other gitignored path (lazy-lock backups,
#          .auto-agents-config, design-decisions, etc. — same reason).
#   3. Run `nvim --headless +Lazy! sync` so the refreshed
#      lazy-lock.json pulls the pinned plugin versions.
#
# rsync replaces an earlier `git archive HEAD | tar -x` pipeline. macOS
# ships bsdtar (libarchive), which trips on `git archive`'s pax global
# header and bails with "`.`: Can't replace existing directory with
# non-directory". GNU tar (Linux) silently handles the same header, so
# the bug only surfaced on macOS. rsync sidesteps the tar format
# entirely and behaves identically across both platforms.
#
# This script is intentionally git-config-agnostic. If the user has
# forked AutoVim and their `~/.config/nvim/.git` tracks the fork, the
# update simply lays new tracked files on top — the fork's history is
# untouched, and `git status` will show the new versions as pending
# changes against the fork (commit / reset / stash as preferred).

set -euo pipefail

REPO="${AUTOVIM_REPO:-https://github.com/yongjohnlee80/autovim.git}"
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
  "md-harpoon.nvim"
  "worktree.nvim"
  "gobugger.nvim"
  "remote-sync.nvim"
)

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; exit 1; }

# Derive the active branch the same way install.sh did. If the user
# has a tracked `.git/` we trust THAT branch over our guess; otherwise
# we pick by OS, matching install.sh's behavior.
detect_branch() {
  if [[ -d "$NVIM_CONFIG/.git" ]] && git -C "$NVIM_CONFIG" rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    git -C "$NVIM_CONFIG" rev-parse --abbrev-ref HEAD
    return
  fi
  case "$(uname -s)" in
    Darwin) echo "mac-os" ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        case "${ID:-}" in
          arch|manjaro|endeavouros)
            if [[ -d "$HOME/.config/omarchy" ]] || command -v omarchy >/dev/null 2>&1; then
              echo "omarchy"
            else
              echo "main"
            fi
            ;;
          *) echo "main" ;;
        esac
      else
        echo "main"
      fi
      ;;
    *) echo "main" ;;
  esac
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
  log "v0.3.10 migration: seeding $target so <C-q> keeps working until you migrate to nvim-dbee"
  cat > "$target" <<'LAZYSQL_LUA'
-- DEPRECATED — preserved by AutoVim's v0.3.10 update.sh migration.
--
-- AutoVim retired the stock lazysql float in v0.3.10 in favor of
-- nvim-dbee (see `:Dbee`, the auto-finder dbase section, and SQL
-- completion via cmp-dbee). This file keeps the old `<C-q>` lazysql
-- float available for users who haven't migrated yet — but it lives in
-- your user-owned `lua/custom/` layer now: AutoVim will never overwrite
-- it on `update.sh`, and you own its lifecycle from here. Delete the
-- file once you're comfortable with the nvim-dbee workflow.
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
        desc = "LazySQL (deprecated; see :Dbee)",
      },
    },
  },
}
LAZYSQL_LUA
}

overlay_tracked_tree() {
  local branch="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  log "Fetching AutoVim ($branch branch) into a temp dir"
  git clone --quiet --depth=1 --branch "$branch" "$REPO" "$tmpdir/autovim"

  log "Overlaying tracked files onto $NVIM_CONFIG (preserving .git/, lua/custom/, every other gitignored path)"
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
This is expected — the AutoVim updater laid new tracked files on top
of whatever your fork's HEAD pointed at. Resolve as you prefer:

  cd "$NVIM_CONFIG"
  git status
  # commit the update into your fork:
  git add -A && git commit -m "AutoVim update"
  # or reset to your fork's upstream:
  git reset --hard origin/<your-branch>
  # or stash to inspect later:
  git stash -u

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

  # Capture pre-overlay markers BEFORE rsync replaces the tracked tree.
  detect_pre_upgrade_lazysql

  overlay_tracked_tree "$branch"
  scaffold_custom_if_missing
  migrate_lazysql_to_custom
  install_autovim_cli
  run_lazy_sync
  run_lazy_update_family
  report_status

  cat >&2 <<EOF

AutoVim updated.

Your customizations are intact:
  * lua/custom/             — never touched (gitignored upstream)
  * .git/ (if any)          — your fork's history is unchanged
  * any other untracked     — left alone

Re-run with different options:
  AUTOVIM_BRANCH=<name>             Force a branch (main | mac-os | omarchy)
  AUTOVIM_REPO=<url>                Pull from a fork
  AUTOVIM_NO_LAZY_SYNC=1            Skip Lazy! sync
  AUTOVIM_NO_FAMILY_UPDATE=1        Skip Lazy update of AutoVim-authored plugins
  AUTOVIM_FAMILY_PLUGINS="a b c"    Override which plugins get the Lazy update

EOF
}

main "$@"
