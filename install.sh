#!/usr/bin/env bash
# AutoVim installer — tier 1.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yongjohnlee80/autovim/main/install.sh | bash
#
# Detects your OS, installs baseline system packages, backs up any existing
# ~/.config/nvim, clones the repo, and runs a headless `Lazy sync` so first
# launch is already warmed up.
#
# SINGLE BRANCH. AutoVim used to ship `main`, `mac-os`, and `omarchy` branches
# and pick one by OS. Every OS-specific behaviour now lives on `main` behind a
# runtime check (`lua/utils/platform.lua`), so there is nothing to pick: macOS
# gets its gopls override and Omarchy boxes follow the system theme from the
# same commit. OS detection below is still used to install the right SYSTEM
# PACKAGES — that part is genuinely per-distro.
#
# Overrides (set as env vars before piping to bash):
#   AUTOVIM_BRANCH=<name>    track a non-default branch (forks / testing)
#   AUTOVIM_REPO=<url>       fork URL (default: upstream)
#   AUTOVIM_SKIP_DEPS=1      skip system-package install (you handle deps manually)
#   AUTOVIM_NO_MISE=1        ignore mise even when present; use the distro's
#                            package manager for everything
#   AUTOVIM_OS_RELEASE=<p>   read distro identity from <p> instead of
#                            /etc/os-release (tests/installer.lua uses this)
#
# Go is a baseline dependency: autodb — the database backend, and AutoVim's
# only SQL surface since v0.4.0 — compiles its daemon through a lazy `build`
# hook, and the Go LSP/debug tooling assumes a toolchain is present.
#
# PORTABLE BASH ONLY. macOS still ships bash 3.2 as /bin/bash, and
# `curl … | bash` runs whatever bash resolves first, so this script must not
# use associative arrays, `mapfile`, or `${var^^}`. Tool/package lookups are
# case statements for exactly that reason.

set -euo pipefail

REPO="${AUTOVIM_REPO:-https://github.com/yongjohnlee80/autovim.git}"
# The hard floor, set by LazyVim (lazyvim/plugins/init.lua aborts below it).
NVIM_MIN="0.11.2"
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# The dependency set, split by WHO CAN PROVIDE IT.
#
# DEV_TOOLS are user-space binaries that mise ships from upstream releases, so
# they are the ones that benefit from mise: the distro's build is frequently
# older (Debian's neovim cannot even start LazyVim) and mise gives every
# platform the same version.
#
# SYS_TOOLS are the ones mise deliberately does NOT carry — they are part of
# the operating system, need a linker and system paths, or must match the
# running libc. `mise registry` has no entry for any of them. These always
# come from the distro package manager (Homebrew on macOS).
DEV_TOOLS="neovim ripgrep fd fzf tmux pandoc go"
SYS_TOOLS="git cc curl rsync"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; exit 1; }

# detect_os maps the running system onto one of: macos, arch, debian, fedora,
# suse, linux-other.
#
# ID FIRST, THEN ID_LIKE, AND THAT SECOND STEP IS THE WHOLE POINT. Matching
# only on ID meant recognising exactly three Arch derivatives by name, so
# CachyOS, Garuda, Arco, Nobara, Zorin, elementary, KDE neon and every future
# respin fell through to "install the dependencies yourself" — on a box whose
# package manager we know perfectly well. `ID_LIKE` is the field the
# os-release spec provides for precisely this question ("a
# space-separated list of operating system identifiers in the same
# (determined by the distribution) close relationship"), and derivatives fill
# it in faithfully because that is what it is for.
#
# The ID_LIKE list is ordered most-related-first by the spec, and this walks
# it in order, so Pop!_OS (`ID_LIKE="ubuntu debian"`) resolves on `ubuntu`
# without ever consulting `debian` — which matters the day the two families
# need different packages.
#
# Reads AUTOVIM_OS_RELEASE when set so the mapping can be exercised against
# fixtures for distros that are not the one running the suite; see
# tests/installer.lua.
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      local osr="${AUTOVIM_OS_RELEASE:-/etc/os-release}"
      if [[ -r "$osr" ]]; then
        # Sourced in a subshell: os-release sets ID/ID_LIKE/NAME/VERSION and
        # more, and none of it should leak into the installer's scope.
        (
          # shellcheck disable=SC1090
          . "$osr"
          # Unquoted ID_LIKE: it is a space-separated LIST and must split.
          # shellcheck disable=SC2086
          for id in "${ID:-}" ${ID_LIKE:-}; do
            case "$id" in
              arch)                          echo "arch";   exit 0 ;;
              ubuntu|debian|raspbian)        echo "debian"; exit 0 ;;
              fedora|rhel|centos)            echo "fedora"; exit 0 ;;
              opensuse*|suse|sles|sle)       echo "suse";   exit 0 ;;
            esac
          done
          echo "linux-other"
        )
      else
        echo "linux-other"
      fi
      ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
}

# AutoVim installs `main` on every platform (see the header). Kept as a
# function so `AUTOVIM_BRANCH` still works for forks and for testing a branch,
# and so the call site in main() does not have to change.
pick_branch() {
  echo "main"
}

# Compare two semver-ish versions. Returns 0 if $1 >= $2, 1 otherwise.
version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]
}

# pkg_name maps a canonical tool name to the package that provides it on $2.
#
# The canonical names are AutoVim's, not any distro's, because no two families
# agree: fd is `fd` on Arch and openSUSE, `fd-find` on Debian and Fedora; the
# Go toolchain is `go`, `golang-go`, or `golang` depending on who you ask; and
# `cc` stands for "whatever pulls in a working C compiler", which is a
# metapackage on Debian and a plain one everywhere else. A compiler is not
# optional — nvim-treesitter builds parsers at install time.
#
# Empty output means "this platform provides it without a package" (the C
# compiler on macOS comes from the Xcode Command Line Tools, not brew).
pkg_name() {
  local tool="$1" os="$2"
  case "$os" in
    macos)
      case "$tool" in
        cc) echo "" ;;
        *)  echo "$tool" ;;
      esac
      ;;
    arch)
      case "$tool" in
        cc) echo "gcc" ;;
        *)  echo "$tool" ;;
      esac
      ;;
    debian)
      case "$tool" in
        cc)     echo "build-essential" ;;
        fd)     echo "fd-find" ;;
        go)     echo "golang-go" ;;
        *)      echo "$tool" ;;
      esac
      ;;
    fedora)
      case "$tool" in
        cc)     echo "gcc" ;;
        fd)     echo "fd-find" ;;
        go)     echo "golang" ;;
        *)      echo "$tool" ;;
      esac
      ;;
    suse)
      case "$tool" in
        cc)     echo "gcc" ;;
        *)      echo "$tool" ;;
      esac
      ;;
    *) echo "" ;;
  esac
}

# pm_install installs the named packages with the platform's package manager.
# Called with zero packages it is a no-op, which is what happens when every
# dev tool came from mise and only the system set is left.
pm_install() {
  local os="$1"; shift
  [[ $# -gt 0 ]] || return 0
  log "Installing with the system package manager: $*"
  case "$os" in
    macos)  brew install "$@" ;;
    arch)   sudo pacman -Syu --needed --noconfirm "$@" ;;
    debian) sudo apt install -y "$@" ;;
    fedora) sudo dnf install -y "$@" ;;
    # --no-recommends keeps a zypper install from dragging in a desktop
    # stack behind pandoc; -n is zypper's non-interactive flag.
    suse)   sudo zypper --non-interactive install --no-recommends "$@" ;;
    *)      return 1 ;;
  esac
}

# mise_usable reports whether mise should be used for the dev tools.
#
# `mise --version` rather than `command -v`: a broken or half-installed mise
# on PATH must not silently swallow the whole dependency install.
mise_usable() {
  [[ "${AUTOVIM_NO_MISE:-0}" != "1" ]] || return 1
  command -v mise >/dev/null 2>&1 || return 1
  mise --version >/dev/null 2>&1
}

# mise_shims_dir is where mise puts the shims that make its tools resolvable
# from a non-activated shell. The installer needs this on PATH for its own
# remaining steps (the nvim floor check and `Lazy sync`) because the user's
# shell rc has not been re-read — and may not activate mise at all.
mise_shims_dir() {
  echo "${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
}

# install_dev_tools installs DEV_TOOLS, preferring mise per tool and falling
# back to the package manager for any tool mise could not provide.
#
# PER TOOL, NOT ALL-OR-NOTHING. mise resolves each tool through its own
# backend (core, aqua, github); a registry gap or a release without a build
# for this platform fails that one tool and says nothing about the rest. An
# all-or-nothing fallback would reinstall six working tools from the distro
# to recover one.
#
# Echoes the tools mise did NOT provide, for the caller to hand to the
# package manager in one transaction.
install_dev_tools_via_mise() {
  local leftovers="" tool
  log "mise found — installing dev tools with it (set AUTOVIM_NO_MISE=1 to use $1 packages instead)"
  for tool in $DEV_TOOLS; do
    # `use -g` installs AND records the version globally, so the tool stays
    # resolvable in later shells rather than only for this process.
    if MISE_YES=1 mise use -g "${tool}@latest" >&2; then
      continue
    fi
    warn "mise could not provide '$tool' — falling back to the system package"
    leftovers="$leftovers $tool"
  done
  echo "$leftovers"
}

install_deps() {
  local os="$1"
  log "Installing system dependencies for $os"

  if [[ "$os" == "linux-other" ]]; then
    die "Could not identify this Linux distribution (no usable ID/ID_LIKE in /etc/os-release).
Install neovim (≥$NVIM_MIN), ripgrep, fd, fzf, git, a C compiler, curl, tmux, rsync, pandoc and go
manually, then re-run with AUTOVIM_SKIP_DEPS=1."
  fi

  if [[ "$os" == "macos" ]]; then
    command -v brew >/dev/null || die "Homebrew not found. Install it from https://brew.sh and re-run."
  fi

  local pm_wanted="" tool pkg
  local dev_leftovers="$DEV_TOOLS"

  if mise_usable; then
    dev_leftovers="$(install_dev_tools_via_mise "$os")"
    # The shims have to be reachable for the rest of THIS run; the user's
    # shell is told about the permanent fix at the end of main().
    PATH="$(mise_shims_dir):$PATH"
    export PATH
  else
    if [[ "${AUTOVIM_NO_MISE:-0}" == "1" ]]; then
      log "AUTOVIM_NO_MISE=1 — using $os packages for every dependency"
    else
      log "mise not found — using $os packages for every dependency (https://mise.jdx.dev to change that)"
    fi
  fi

  # One transaction for everything the package manager still owes us: the
  # system set always, plus whatever mise did not cover.
  for tool in $SYS_TOOLS $dev_leftovers; do
    pkg="$(pkg_name "$tool" "$os")"
    [[ -n "$pkg" ]] && pm_wanted="$pm_wanted $pkg"
  done

  # apt needs its index refreshed before an install can resolve anything.
  if [[ "$os" == "debian" && -n "${pm_wanted// /}" ]]; then
    sudo apt update
  fi

  # shellcheck disable=SC2086
  pm_install "$os" $pm_wanted

  # Ubuntu ships fd as `fdfind`. Most nvim plugins expect `fd`. Only relevant
  # when fd came from apt — a mise-installed fd is already named `fd`.
  if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    warn "Symlinked fdfind → ~/.local/bin/fd. Ensure ~/.local/bin is on your PATH."
  fi
}

# ensure_nvim enforces LazyVim's floor on EVERY platform, after the
# dependency install has had its turn.
#
# The floor is 0.11.2, set by LazyVim, and it is a HARD abort, not a
# degradation: lazyvim/plugins/init.lua prints "LazyVim requires Neovim >=
# 0.11.2", waits for a keypress and quits. This gate said 0.10.0 until v0.4.2,
# so a Debian box already carrying nvim 0.10.x passed the check, skipped the
# snap, and then could not start. Keep this in step with LazyVim's requirement
# when it moves.
#
# UNIVERSAL, NOT DEBIAN-ONLY, which it was until this version. Any distro can
# hand you an nvim below the floor — openSUSE Leap and the RHEL rebuilds
# routinely do — and the old placement meant the installer only ever noticed
# on one family. It runs after install_deps so it judges what is actually on
# PATH now, including a mise shim.
ensure_nvim() {
  local os="$1" v
  if command -v nvim >/dev/null; then
    v="$(nvim --version | head -1 | awk '{print $2}' | sed 's/^v//')"
    if version_ge "$v" "$NVIM_MIN"; then
      log "neovim $v satisfies the ≥$NVIM_MIN floor"
      return 0
    fi
    warn "neovim $v is below LazyVim's ≥$NVIM_MIN floor"
  else
    warn "neovim is not on PATH after the dependency install"
  fi

  # snap is the long-standing escape hatch on Debian/Ubuntu, whose apt nvim
  # is almost always too old. Everywhere else, mise is the answer that does
  # not need root.
  if [[ "$os" == "debian" ]] && command -v snap >/dev/null; then
    log "Installing neovim via snap (apt's version is too old for LazyVim)"
    sudo snap install nvim --classic
    hash -r
    if command -v nvim >/dev/null; then
      v="$(nvim --version | head -1 | awk '{print $2}' | sed 's/^v//')"
      version_ge "$v" "$NVIM_MIN" && return 0
    fi
  fi

  die "neovim ≥$NVIM_MIN required (LazyVim aborts below this).
Install a newer neovim — 'mise use -g neovim@latest' needs no root — then re-run with AUTOVIM_SKIP_DEPS=1."
}

clone_config() {
  local branch="$1"
  if [[ -d "$NVIM_CONFIG" ]]; then
    local backup="${NVIM_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing config: $NVIM_CONFIG → $backup"
    mv "$NVIM_CONFIG" "$backup"
  fi
  log "Cloning AutoVim ($branch branch) into $NVIM_CONFIG"
  git clone --branch "$branch" "$REPO" "$NVIM_CONFIG"
}

# Scaffold the user-owned custom layer from docs/custom-example/ on
# fresh install. The layer is gitignored, so it never appears as
# untracked changes against AutoVim's tree and never gets touched by
# `update.sh`. Skipped if `lua/custom/` already exists — a re-run of
# install.sh against an existing install must not clobber user edits.
scaffold_custom() {
  local target="$NVIM_CONFIG/lua/custom"
  local source="$NVIM_CONFIG/docs/custom-example"
  if [[ -d "$target" ]]; then
    log "Custom layer already present: $target (leaving it as-is)"
    return
  fi
  if [[ ! -d "$source" ]]; then
    warn "docs/custom-example missing in this AutoVim checkout — skipping custom-layer scaffold"
    return
  fi
  log "Scaffolding user custom layer: $target"
  cp -r "$source" "$target"
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
  log "Installed autovim CLI: $link → $src"

  case ":$PATH:" in
    *":$bindir:"*) ;;
    *) warn "$bindir is not on PATH — add this to your shell rc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
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
  branch="${AUTOVIM_BRANCH:-$(pick_branch)}"

  log "AutoVim installer"
  log "  OS:     $os"
  log "  Branch: $branch"
  log "  Target: $NVIM_CONFIG"

  if [[ "${AUTOVIM_SKIP_DEPS:-0}" != "1" ]]; then
    install_deps "$os"
    ensure_nvim "$os"
  else
    log "AUTOVIM_SKIP_DEPS=1 — skipping system package install"
  fi
  clone_config "$branch"
  scaffold_custom
  install_autovim_cli
  bootstrap_plugins

  # Said only when it is true: a mise-installed nvim is reachable right now
  # because install_deps put the shims on PATH for this process, and will
  # NOT be in the user's next shell unless mise is activated there.
  if mise_usable; then
    cat >&2 <<EOF

mise provided your dev tools. If a new shell cannot find nvim, activate mise
in your shell rc (pick the one you use):

  echo 'eval "\$(mise activate bash)"' >> ~/.bashrc
  echo 'eval "\$(mise activate zsh)'"'"'  >> ~/.zshrc
  echo 'mise activate fish | source'     >> ~/.config/fish/config.fish

or put the shims on PATH directly:

  export PATH="$(mise_shims_dir):\$PATH"
EOF
  fi

  cat >&2 <<EOF

AutoVim installed.

Next:
  nvim                  # launch; the AUTOVIM splash means it's wired up
  :checkhealth          # confirm everything resolved
  :Lazy                 # plugin manager UI

Branch: $branch
Config: $NVIM_CONFIG

Re-run with different options:
  AUTOVIM_BRANCH=<name>   Track a non-default branch (forks / testing)
  AUTOVIM_REPO=<url>      Install from a fork
  AUTOVIM_SKIP_DEPS=1     Skip system package install
  AUTOVIM_NO_MISE=1       Use distro packages even when mise is installed

EOF
}

# SOURCING THIS FILE MUST NOT INSTALL ANYTHING. tests/installer.lua sources it
# to call detect_os/pkg_name against fixtures; without this guard, loading the
# functions would run a real install on the test machine.
if [[ "${AUTOVIM_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
