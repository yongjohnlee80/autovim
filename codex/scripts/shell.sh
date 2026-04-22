#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  shell.sh -t <1..4> <shell command>
  shell.sh --term <1..4> <shell command>

Examples:
  shell.sh -t 1 ls -al
  shell.sh --term=2 "npm run dev"
EOF
}

die() {
  printf 'shell: %s\n' "$*" >&2
  exit 1
}

require_nvim_terminal() {
  if [ -z "${NVIM:-}" ]; then
    die "this command must be run from inside a Neovim terminal (\$NVIM is not set)"
  fi

  if [ ! -S "${NVIM}" ]; then
    die "the current \$NVIM socket is not available: ${NVIM}"
  fi
}

rpc_alive() {
  local socket="${1:-}"
  [ -n "${socket}" ] || return 1
  [ -S "${socket}" ] || return 1
  nvim --server "${socket}" --remote-expr '1' >/dev/null 2>&1
}

cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/codex-shell"
cache_file="${cache_dir}/nvim-rpc-server"

discover_server() {
  local source=""
  local server=""

  require_nvim_terminal
  mkdir -p "${cache_dir}"

  if [ -f "${cache_file}" ]; then
    IFS="$(printf '\t')" read -r source server < "${cache_file}" || true
    if [ "${source}" = "${NVIM}" ] && rpc_alive "${server}"; then
      printf '%s\n' "${server}"
      return 0
    fi
  fi

  if ! rpc_alive "${NVIM}"; then
    die "failed to reach Neovim over \$NVIM=${NVIM}"
  fi

  server="$(nvim --server "${NVIM}" --remote-expr 'v:servername' 2>/dev/null | tr -d '\r\n')"
  if ! rpc_alive "${server}"; then
    server="${NVIM}"
  fi

  if ! rpc_alive "${server}"; then
    die "failed to discover a working Neovim RPC server"
  fi

  printf '%s\t%s\n' "${NVIM}" "${server}" > "${cache_file}"
  printf '%s\n' "${server}"
}

term=""
cmd=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -t|--term)
      [ "$#" -ge 2 ] || die "missing value for $1"
      term="$2"
      shift 2
      ;;
    --term=*)
      term="${1#*=}"
      shift
      ;;
    -t=*)
      term="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      cmd=("$@")
      break
      ;;
    *)
      cmd=("$@")
      break
      ;;
  esac
done

[ -n "${term}" ] || die "missing -t/--term"
case "${term}" in
  1|2|3|4) ;;
  *) die "terminal must be one of 1, 2, 3, or 4" ;;
esac

[ "${#cmd[@]}" -gt 0 ] || die "missing shell command"

server="$(discover_server)"
if [ "${#cmd[@]}" -eq 1 ]; then
  command_text="${cmd[0]}"
else
  printf -v command_text '%q ' "${cmd[@]}"
  command_text="${command_text% }"
fi

payload="$(printf '%s' "${command_text}" | base64 | tr -d '\n')"

nvim --server "${server}" --remote-expr \
  "luaeval('require(\"utils.term_send\").send(_A[1], vim.base64.decode(_A[2])) and 1 or 0', [${term}, '${payload}'])" \
  >/dev/null
