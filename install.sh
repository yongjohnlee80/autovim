#!/usr/bin/env bash
# AutoVIM installer — tier 1.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yongjohnlee80/autovim/main/install.sh | bash
#
# Detects your OS + Omarchy presence, picks the matching branch,
# installs baseline system packages, backs up any existing ~/.config/nvim,
# clones the repo, and runs a headless `Lazy sync` so first launch is
# already warmed up.
#
# Overrides (set as env vars before piping to bash):
#   AUTOVIM_BRANCH=<name>    force a specific branch (main | mac-os | omarchy)
#   AUTOVIM_REPO=<url>       fork URL (default: upstream)
#   AUTOVIM_SKIP_DEPS=1      skip system-package install (you handle deps manually)

set -euo pipefail

REPO="${AUTOVIM_REPO:-https://github.com/yongjohnlee80/autovim.git}"
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; exit 1; }

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
          arch|manjaro|endeavouros)    echo "arch" ;;
          ubuntu|debian|pop|linuxmint) echo "debian" ;;
          fedora|rhel|centos|rocky)    echo "fedora" ;;
          *) echo "linux-other" ;;
        esac
      else
        echo "linux-other"
      fi
      ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
}

pick_branch() {
  local os="$1"
  case "$os" in
    macos) echo "mac-os" ;;
    arch)
      # Omarchy places its config + binary here. Fall back to `main` on
      # plain Arch installs.
      if [[ -d "$HOME/.config/omarchy" ]] || command -v omarchy >/dev/null 2>&1; then
        echo "omarchy"
      else
        echo "main"
      fi
      ;;
    *) echo "main" ;;
  esac
}

# Compare two semver-ish versions. Returns 0 if $1 >= $2, 1 otherwise.
version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]
}

install_deps() {
  local os="$1"
  log "Installing system dependencies for $os"

  case "$os" in
    macos)
      command -v brew >/dev/null || die "Homebrew not found. Install it from https://brew.sh and re-run."
      brew install neovim ripgrep fd fzf git glow
      ;;

    arch)
      sudo pacman -Syu --needed --noconfirm neovim ripgrep fd fzf git gcc curl glow
      ;;

    debian)
      sudo apt update
      sudo apt install -y ripgrep fd-find fzf git build-essential curl

      # apt's nvim is almost always too old for LazyVim (<0.10). Use snap.
      local need_nvim=1
      if command -v nvim >/dev/null; then
        local v
        v="$(nvim --version | head -1 | awk '{print $2}' | sed 's/^v//')"
        if version_ge "$v" "0.10.0"; then
          need_nvim=0
        fi
      fi
      if [[ "$need_nvim" == "1" ]]; then
        if command -v snap >/dev/null; then
          log "Installing neovim via snap (apt's version is too old for LazyVim)"
          sudo snap install nvim --classic
        else
          warn "neovim ≥0.10 not found and snap is unavailable. Install nvim manually (PPA or AppImage), then re-run with AUTOVIM_SKIP_DEPS=1."
          die "neovim ≥0.10 required"
        fi
      fi

      # Ubuntu ships fd as `fdfind`. Most nvim plugins expect `fd`.
      if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        warn "Symlinked fdfind → ~/.local/bin/fd. Ensure ~/.local/bin is on your PATH."
      fi

      warn "glow isn't in apt. Install manually if you want <leader>mp markdown preview: https://github.com/charmbracelet/glow#install"
      ;;

    fedora)
      sudo dnf install -y neovim ripgrep fd-find fzf git gcc curl
      warn "glow isn't in dnf. Install manually if you want <leader>mp: https://github.com/charmbracelet/glow#install"
      ;;

    *)
      die "Automatic dep install isn't supported on this system. Install neovim (≥0.10), ripgrep, fd, fzf, git, gcc, curl manually, then re-run with AUTOVIM_SKIP_DEPS=1."
      ;;
  esac

  # lazysql (TUI SQL client on <C-q>) — go install works on any host with Go.
  if ! command -v lazysql >/dev/null; then
    if command -v go >/dev/null; then
      log "Installing lazysql via go install"
      go install github.com/jorgerojas26/lazysql@latest || warn "lazysql install failed; <C-q> SQL float will no-op until fixed"
    else
      warn "lazysql not installed (needs Go). <C-q> SQL float will no-op until installed: https://github.com/jorgerojas26/lazysql"
    fi
  fi
}

clone_config() {
  local branch="$1"
  if [[ -d "$NVIM_CONFIG" ]]; then
    local backup="${NVIM_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing config: $NVIM_CONFIG → $backup"
    mv "$NVIM_CONFIG" "$backup"
  fi
  log "Cloning AutoVIM ($branch branch) into $NVIM_CONFIG"
  git clone --branch "$branch" "$REPO" "$NVIM_CONFIG"
}

bootstrap_plugins() {
  if ! command -v nvim >/dev/null; then
    warn "nvim not on PATH — skipping Lazy sync. Open nvim manually once your PATH is refreshed; plugins will install on first launch."
    return
  fi
  log "Syncing plugins via Lazy (first launch will be faster)"
  nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "Lazy sync exited non-zero — finish interactively on first nvim launch."
}

main() {
  local os branch
  os="$(detect_os)"
  branch="${AUTOVIM_BRANCH:-$(pick_branch "$os")}"

  log "AutoVIM installer"
  log "  OS:     $os"
  log "  Branch: $branch"
  log "  Target: $NVIM_CONFIG"

  if [[ "${AUTOVIM_SKIP_DEPS:-0}" != "1" ]]; then
    install_deps "$os"
  else
    log "AUTOVIM_SKIP_DEPS=1 — skipping system package install"
  fi
  clone_config "$branch"
  bootstrap_plugins

  cat >&2 <<EOF

AutoVIM installed.

Next:
  nvim                  # launch; the AUTOVIM splash means it's wired up
  :checkhealth          # confirm everything resolved
  :Lazy                 # plugin manager UI

Branch: $branch
Config: $NVIM_CONFIG

Re-run with different options:
  AUTOVIM_BRANCH=<name>   Force a branch (main | mac-os | omarchy)
  AUTOVIM_REPO=<url>      Install from a fork
  AUTOVIM_SKIP_DEPS=1     Skip system package install

EOF
}

main "$@"
