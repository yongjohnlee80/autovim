#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bundle_root="$(CDPATH= cd -- "${script_dir}/.." && pwd)"
codex_home="${CODEX_HOME:-$HOME/.codex}"

mkdir -p "${codex_home}/skills" "${codex_home}/commands" "${codex_home}/commands/skills"

link_one() {
  local source_path="$1"
  local target_path="$2"
  local source_real=""
  local target_real=""

  mkdir -p "$(dirname "${target_path}")"

  if [ -L "${target_path}" ]; then
    source_real="$(readlink -f "${source_path}")"
    target_real="$(readlink -f "${target_path}")"
    if [ "${source_real}" = "${target_real}" ]; then
      printf '[ok] %s already linked\n' "${target_path}"
      return 0
    fi
    printf '[warn] leaving existing symlink in place: %s -> %s\n' "${target_path}" "$(readlink "${target_path}")" >&2
    return 0
  fi

  if [ -e "${target_path}" ]; then
    printf '[warn] leaving existing path in place: %s\n' "${target_path}" >&2
    return 0
  fi

  ln -s "${source_path}" "${target_path}"
  printf '[link] %s -> %s\n' "${target_path}" "${source_path}"
}

link_one "${bundle_root}/skills/shell" "${codex_home}/skills/shell"
link_one "${bundle_root}/skills/toggle-diff-editor" "${codex_home}/skills/toggle-diff-editor"
link_one "${bundle_root}/commands/toggle-diff-editor.md" "${codex_home}/commands/toggle-diff-editor.md"
link_one "${bundle_root}/commands/skills/shell.md" "${codex_home}/commands/skills/shell.md"
