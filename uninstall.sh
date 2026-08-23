#!/usr/bin/env bash
# AutoVim uninstaller — removes AutoVim *and* Neovim.
#
# Usage:
#   ~/.config/nvim/uninstall.sh              # inventory, then ask about your data
#   ~/.config/nvim/uninstall.sh --dry-run    # inventory only, touch nothing
#   ~/.config/nvim/uninstall.sh --keep-data  # keep all user data, no prompts
#   ~/.config/nvim/uninstall.sh --purge      # remove everything, no prompts
#
# Flags:
#   --dry-run       print the inventory and exit; remove nothing
#   --keep-data     don't ask — keep every user-data item listed below
#   --purge         don't ask — remove every user-data item listed below
#   --keep-neovim   remove AutoVim but leave the Neovim package installed
#   --force         with --purge, proceed even when the knowledge base has
#                   uncommitted or unpushed work
#
# ALWAYS REMOVED (AutoVim's own installed footprint)
#   ~/.config/nvim          the AutoVim clone
#   ~/.local/share/nvim     plugins (lazy), Mason binaries, autodb build cache
#   ~/.local/state/nvim     shada, sessions, theme cache, nav-modal shortcuts
#   ~/.cache/nvim           compiled Lua, treesitter artifacts
#   ~/.local/bin/autovim    the workspace-manager symlink
#   the Neovim package      via pacman / apt / dnf / brew / snap
#
# ASKED ABOUT, ONE AT A TIME (your data — none of it is AutoVim's to assume)
#   .auto-agents-config/    agent TOMLs, mailboxes, and the knowledge base.
#                           The KB is a git repo; uncommitted work in it exists
#                           nowhere else, so its status is shown before you
#                           decide.
#   lua/custom/             your own gitignored config layer
#   ~/.config/autovim/      the workspace registry (workspaces.tsv)
#   ~/.local/share/autodb   database connections, notes, script history
#
# The first two live INSIDE ~/.config/nvim, so "keep" means moving them out to a
# timestamped rescue directory before the config is deleted. The last two live
# outside it, so "keep" simply leaves them where they are.
#
# Your project directories, worktrees and git repos are never touched.
#
# Re-install with:
#   curl -fsSL https://raw.githubusercontent.com/yongjohnlee80/autovim/main/install.sh | bash

set -euo pipefail

DRY_RUN=0 KEEP_DATA=0 PURGE=0 KEEP_NEOVIM=0 FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=1 ;;
    --keep-data)   KEEP_DATA=1 ;;
    --purge)       PURGE=1 ;;
    --keep-neovim) KEEP_NEOVIM=1 ;;
    --force)       FORCE=1 ;;
    -h|--help)     sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             printf 'unknown flag: %s (try --help)\n' "$arg" >&2; exit 2 ;;
  esac
done
(( KEEP_DATA && PURGE )) && { printf '%s\n' "--keep-data and --purge are mutually exclusive" >&2; exit 2; }

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; exit 1; }

NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
NVIM_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
NVIM_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"
AUTOVIM_BIN="$HOME/.local/bin/autovim"
AGENTS_DIR="$NVIM_CONFIG/.auto-agents-config"
CUSTOM_DIR="$NVIM_CONFIG/lua/custom"
KB_DIR="$AGENTS_DIR/kb"
WORKSPACES="${XDG_CONFIG_HOME:-$HOME/.config}/autovim"
AUTODB_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/autodb"
RESCUE="$HOME/autovim-rescue-$(date +%Y%m%d-%H%M%S)"

# Never let a bad expansion turn into `rm -rf /` or `rm -rf $HOME`.
safe_rm() {
  local target="$1"
  [[ -n "$target" ]]         || die "refusing to remove an empty path"
  [[ "$target" != "/" ]]     || die "refusing to remove /"
  [[ "$target" != "$HOME" ]] || die "refusing to remove \$HOME"
  case "$target" in
    "$HOME"/*) : ;;
    *) die "refusing to remove a path outside \$HOME: $target" ;;
  esac
  [[ -e "$target" || -L "$target" ]] || return 0
  if (( DRY_RUN )); then printf '   would remove  %s\n' "$target"; return 0; fi
  rm -rf -- "$target"
  printf '   removed       %s\n' "$target"
}

detect_pm() {
  case "$(uname -s)" in
    Darwin) command -v brew >/dev/null && echo brew || echo none ;;
    Linux)
      if   command -v pacman >/dev/null && pacman -Qq neovim >/dev/null 2>&1; then echo pacman
      elif command -v dpkg   >/dev/null && dpkg -s neovim  >/dev/null 2>&1; then echo apt
      elif command -v rpm    >/dev/null && rpm -q neovim   >/dev/null 2>&1; then echo dnf
      elif command -v snap   >/dev/null && snap list nvim  >/dev/null 2>&1; then echo snap
      else echo none; fi ;;
    *) echo none ;;
  esac
}

human() { du -sh "$1" 2>/dev/null | cut -f1 || echo '?'; }

# Knowledge-base status, surfaced before any decision about the agent config.
kb_state=""
kb_unsaved=0
if [[ -d "$KB_DIR/.git" ]]; then
  dirty="$(git -C "$KB_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  # Three distinct states, because "unknown" is not the same as "unpushed".
  # A KB with no upstream is not merely un-synced — it exists nowhere else at
  # all, which is a stronger reason to warn, not a weaker one. Reporting it as
  # "? unpushed commits" (the previous behaviour) was both confusing and made a
  # remote-less KB look like a counting failure.
  if git -C "$KB_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    unpushed="$(git -C "$KB_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    kb_state="$dirty uncommitted file(s), $unpushed unpushed commit(s)"
    [[ "$dirty" != "0" || "$unpushed" != "0" ]] && kb_unsaved=1 || true
  else
    kb_state="$dirty uncommitted file(s); NO upstream remote — this KB exists only on this machine"
    kb_unsaved=1
  fi
fi

PM="$(detect_pm)"

printf '\n--- AutoVim uninstall ---\n\nAlways removed:\n'
for p in "$NVIM_CONFIG" "$NVIM_DATA" "$NVIM_STATE" "$NVIM_CACHE"; do
  [[ -e "$p" ]] && printf '  %-44s %s\n' "$p" "$(human "$p")" || true
done
[[ -e "$AUTOVIM_BIN" || -L "$AUTOVIM_BIN" ]] && printf '  %-44s\n' "$AUTOVIM_BIN" || true
if   (( KEEP_NEOVIM ));   then printf '  (Neovim package kept — --keep-neovim)\n'
elif [[ "$PM" == none ]]; then printf '  (Neovim package skipped — no supported package manager found)\n'
else printf '  the Neovim package, via %s\n' "$PM"; fi
printf '\n'

if (( DRY_RUN )); then
  printf 'Your data (you would be asked about each):\n'
  [[ -d "$AGENTS_DIR" ]]  && printf '  %-44s %s\n' "$AGENTS_DIR"  "$(human "$AGENTS_DIR")"
  [[ -n "$kb_state" ]]    && printf '    knowledge base: %s\n' "$kb_state"
  [[ -d "$CUSTOM_DIR" ]]  && printf '  %-44s %s\n' "$CUSTOM_DIR"  "$(human "$CUSTOM_DIR")"
  [[ -d "$WORKSPACES" ]]  && printf '  %-44s %s\n' "$WORKSPACES"  "$(human "$WORKSPACES")"
  [[ -d "$AUTODB_DATA" ]] && printf '  %-44s %s\n' "$AUTODB_DATA" "$(human "$AUTODB_DATA")" || true
  printf '\n'; log "--dry-run: nothing was changed."; exit 0
fi

# ── decide, per item ─────────────────────────────────────────────────────
# Sets DECIDE_<key>=keep|remove. Default on a bare <Enter> is always KEEP:
# losing data to a stray keypress is the failure mode worth designing out.
declare -A DECIDE=()
ask() {
  local key="$1" path="$2" blurb="$3" extra="${4:-}"
  [[ -e "$path" ]] || { DECIDE[$key]=absent; return 0; }
  if (( KEEP_DATA )); then DECIDE[$key]=keep;   return 0; fi
  if (( PURGE ));     then DECIDE[$key]=remove; return 0; fi
  printf '\n  %s\n    %s  (%s)\n' "$blurb" "$path" "$(human "$path")"
  [[ -n "$extra" ]] && printf '    %s\n' "$extra" || true
  printf '    Remove it? [y/N] '
  local reply; read -r reply
  case "$reply" in [yY]|[yY][eE][sS]) DECIDE[$key]=remove ;; *) DECIDE[$key]=keep ;; esac
}

if (( ! KEEP_DATA && ! PURGE )); then
  printf 'Now your data. Enter alone keeps it.\n'
fi
kb_note=""
(( kb_unsaved )) && kb_note="WARNING: the knowledge base has unsaved work ($kb_state) — it exists nowhere else."
[[ -z "$kb_note" && -n "$kb_state" ]] && kb_note="knowledge base: $kb_state (all pushed)" || true
ask agents  "$AGENTS_DIR"  "Agent config, mailboxes and the knowledge base" "$kb_note"
ask custom  "$CUSTOM_DIR"  "Your own config layer (lua/custom)"
ask ws      "$WORKSPACES"  "Workspace registry (autovim workspaces.tsv)"
ask autodb  "$AUTODB_DATA" "autodb data — connections, notes, script history"

if (( PURGE )) && (( kb_unsaved )) && [[ "${DECIDE[agents]:-absent}" == "remove" ]] && (( ! FORCE )); then
  warn "The knowledge base has unsaved work ($kb_state)."
  warn "Commit and push it first:  cd $KB_DIR && git add -A && git commit && git push"
  die  "refusing to purge unsaved KB work (override with --force)"
fi

printf '\nAbout to remove AutoVim and Neovim'
if [[ "${DECIDE[agents]:-}" == "remove" || "${DECIDE[custom]:-}" == "remove" \
   || "${DECIDE[ws]:-}"     == "remove" || "${DECIDE[autodb]:-}" == "remove" ]]; then
  printf ', plus the data you marked for removal'
fi
printf '.\nType "yes" to proceed: '
read -r reply; [[ "$reply" == "yes" ]] || { log "aborted — nothing was changed."; exit 0; }

# ── rescue what is kept but lives inside the config dir ──────────────────
rescue() {
  local src="$1"
  [[ -d "$src" ]] || return 0
  mkdir -p "$RESCUE"
  mv -- "$src" "$RESCUE/$(basename "$src")"
  printf '   rescued       %s -> %s/%s\n' "$src" "$RESCUE" "$(basename "$src")"
}
printf '\n'
[[ "${DECIDE[agents]:-}" == "keep" ]] && rescue "$AGENTS_DIR" || true
[[ "${DECIDE[custom]:-}" == "keep" ]] && rescue "$CUSTOM_DIR" || true

log "Removing AutoVim"
safe_rm "$NVIM_CONFIG"    # takes any inside-config data marked for removal
safe_rm "$NVIM_DATA"
safe_rm "$NVIM_STATE"
safe_rm "$NVIM_CACHE"
safe_rm "$AUTOVIM_BIN"
[[ "${DECIDE[ws]:-}"     == "remove" ]] && safe_rm "$WORKSPACES" || true
[[ "${DECIDE[autodb]:-}" == "remove" ]] && safe_rm "$AUTODB_DATA" || true

if (( ! KEEP_NEOVIM )) && [[ "$PM" != none ]]; then
  log "Removing the Neovim package via $PM"
  case "$PM" in
    pacman) sudo pacman -Rns --noconfirm neovim || warn "pacman removal failed" ;;
    apt)    sudo apt-get remove -y neovim && sudo apt-get autoremove -y || warn "apt removal failed" ;;
    dnf)    sudo dnf remove -y neovim || warn "dnf removal failed" ;;
    snap)   sudo snap remove nvim || warn "snap removal failed" ;;
    brew)   brew uninstall neovim || warn "brew removal failed" ;;
  esac
fi

printf '\n'
log "AutoVim removed."
if [[ -d "$RESCUE" ]]; then
  log "Kept data moved to: $RESCUE"
  log "  A re-install will NOT pick it up automatically. Move it back by hand:"
  [[ -d "$RESCUE/.auto-agents-config" ]] && log "    mv $RESCUE/.auto-agents-config ~/.config/nvim/" || true
  [[ -d "$RESCUE/custom" ]]              && log "    mv $RESCUE/custom              ~/.config/nvim/lua/"
fi
for k in ws:"$WORKSPACES" autodb:"$AUTODB_DATA"; do
  key="${k%%:*}"; path="${k#*:}"
  [[ "${DECIDE[$key]:-}" == "keep" && -e "$path" ]] && log "Left in place: $path" || true
done
