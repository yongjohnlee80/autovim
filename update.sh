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
#      `git archive | tar -x`. This naturally:
#        * skips `.git/` (so the user's own git config — including a
#          fork remote, or no .git/ at all — survives the update),
#        * skips `lua/custom/` (gitignored upstream → not in the
#          archive → user customizations untouched),
#        * skips every other gitignored path (lazy-lock backups,
#          .auto-agents-config, design-decisions, etc.).
#   3. Run `nvim --headless +Lazy! sync` so the refreshed
#      lazy-lock.json pulls the pinned plugin versions.
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

overlay_tracked_tree() {
  local branch="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  log "Fetching AutoVim ($branch branch) into a temp dir"
  git clone --quiet --depth=1 --branch "$branch" "$REPO" "$tmpdir/autovim"

  log "Overlaying tracked files onto $NVIM_CONFIG (preserving .git/, lua/custom/, every other gitignored path)"
  # `git archive HEAD` emits a tar of the COMMITTED tree only — no
  # .git/, no untracked files, no gitignored files. We pipe straight
  # into tar so the user dir receives exactly the upstream snapshot
  # of tracked files (and nothing else).
  git -C "$tmpdir/autovim" archive --format=tar HEAD | tar -x -C "$NVIM_CONFIG"
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

  overlay_tracked_tree "$branch"
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
