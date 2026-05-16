#!/usr/bin/env bash
# autovim — tmux + nvim workspace manager.
#
# A workspace is a named (session, working-directory) pair persisted in
# ~/.config/autovim/workspaces.tsv. Starting a workspace creates (or
# reattaches to) a tmux session in that directory with `nvim .` running
# in the first pane. The session survives terminal-app shutdowns and
# network drops — reattach with `autovim <name>` to resume.
#
# usage:
#   autovim new                    create a workspace (prompts for name + dir)
#   autovim <name>                 attach or start workspace
#   autovim edit <name>            edit workspace (prompts; blank keeps current)
#   autovim rm <name>              remove workspace + kill its session if alive
#   autovim ls                     list workspaces and session status
#   autovim mem | autovim meme     RSS per live tmux session
#   autovim kill <name>            kill a session (workspace entry kept)
#   autovim -h | --help            help

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autovim"
CONFIG_FILE="$CONFIG_DIR/workspaces.tsv"
RESERVED='new edit rm ls mem meme kill help -h --help'
NAME_REGEX='^[A-Za-z0-9_-]+$'

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; exit 1; }

ensure_config() {
	mkdir -p "$CONFIG_DIR"
	[[ -f "$CONFIG_FILE" ]] || : > "$CONFIG_FILE"
}

require_tmux() {
	command -v tmux >/dev/null || die "tmux not found on PATH"
}

# Expand a leading ~ to $HOME without eval.
expand_path() {
	local p="$1"
	case "$p" in
		"~")    printf '%s\n' "$HOME" ;;
		"~/"*)  printf '%s\n' "$HOME/${p#~/}" ;;
		*)      printf '%s\n' "$p" ;;
	esac
}

is_reserved() {
	local n="$1" r
	for r in $RESERVED; do
		[[ "$n" == "$r" ]] && return 0
	done
	return 1
}

validate_name() {
	local n="$1"
	[[ -n "$n" ]] || die "workspace name required"
	[[ "$n" =~ $NAME_REGEX ]] || die "invalid name '$n' — use letters, digits, '_' or '-'"
	is_reserved "$n" && die "'$n' is a reserved subcommand — pick another name"
	return 0
}

# get_dir <name> — prints dir on stdout, exits non-zero if not found.
get_dir() {
	local name="$1"
	awk -F'\t' -v n="$name" '$1 == n { print $2; found=1; exit } END { exit !found }' "$CONFIG_FILE"
}

# upsert <name> <dir>
upsert() {
	local name="$1" dir="$2" tmp
	tmp="$(mktemp)"
	awk -F'\t' -v n="$name" '$1 != n' "$CONFIG_FILE" > "$tmp"
	printf '%s\t%s\n' "$name" "$dir" >> "$tmp"
	mv "$tmp" "$CONFIG_FILE"
}

remove_entry() {
	local name="$1" tmp
	tmp="$(mktemp)"
	awk -F'\t' -v n="$name" '$1 != n' "$CONFIG_FILE" > "$tmp"
	mv "$tmp" "$CONFIG_FILE"
}

session_exists() {
	tmux has-session -t="$1" 2>/dev/null
}

# Attach to session $1, switching client if we're already inside tmux.
attach_or_switch() {
	local name="$1"
	if [[ -n "${TMUX:-}" ]]; then
		tmux switch-client -t "$name"
	else
		tmux attach-session -t "$name"
	fi
}

cmd_new() {
	local name dir cwd
	cwd="$(pwd)"
	read -rp 'Enter workspace name: ' name
	validate_name "$name"
	read -rp "Enter desired workspace directory [$cwd]: " dir
	if [[ -z "$dir" ]]; then
		dir="$cwd"
	else
		dir="$(expand_path "$dir")"
	fi
	[[ -d "$dir" ]] || die "no such directory: '$dir' — provide an existing absolute or ~/ path, or leave blank to use the current directory ($cwd)"

	if get_dir "$name" >/dev/null 2>&1; then
		local reply
		read -rp "workspace '$name' already exists — overwrite? [y/N] " reply
		[[ "$reply" =~ ^[Yy]$ ]] || { log "aborted"; return; }
	fi

	upsert "$name" "$dir"
	log "saved: $name → $dir"
}

cmd_edit() {
	local name="${1:-}"
	[[ -n "$name" ]] || die "usage: autovim edit <name>"
	local cur_dir
	cur_dir="$(get_dir "$name")" || die "no such workspace: $name"

	local new_name new_dir
	read -rp "Workspace name [$name]: " new_name
	new_name="${new_name:-$name}"
	validate_name "$new_name"

	read -rp "Workspace directory [$cur_dir]: " new_dir
	new_dir="${new_dir:-$cur_dir}"
	new_dir="$(expand_path "$new_dir")"
	[[ -d "$new_dir" ]] || die "directory not found: $new_dir"

	if [[ "$new_name" != "$name" ]]; then
		if get_dir "$new_name" >/dev/null 2>&1; then
			die "workspace '$new_name' already exists — rm it first or pick a different name"
		fi
		remove_entry "$name"
		if session_exists "$name"; then
			tmux rename-session -t "$name" "$new_name"
			log "renamed live session $name → $new_name"
		fi
	fi
	upsert "$new_name" "$new_dir"
	log "updated: $new_name → $new_dir"
}

cmd_rm() {
	local name="${1:-}"
	[[ -n "$name" ]] || die "usage: autovim rm <name>"
	get_dir "$name" >/dev/null || die "no such workspace: $name"
	if session_exists "$name"; then
		tmux kill-session -t "$name"
		log "killed session: $name"
	fi
	remove_entry "$name"
	log "removed: $name"
}

cmd_ls() {
	if [[ ! -s "$CONFIG_FILE" ]]; then
		echo "no workspaces — create one with: autovim new"
		return
	fi
	printf '%-20s %-50s %s\n' NAME DIR SESSION
	local name dir status
	while IFS=$'\t' read -r name dir; do
		[[ -z "$name" ]] && continue
		status='-'
		session_exists "$name" && status='alive'
		printf '%-20s %-50s %s\n' "$name" "$dir" "$status"
	done < "$CONFIG_FILE"
}

# Sum RSS (KB) for pid and all descendants. macOS + Linux compatible.
pstree_rss() {
	local root="$1"
	local pids="$root"
	local frontier="$root"
	local next children
	while [[ -n "$frontier" ]]; do
		next=''
		for p in $frontier; do
			children="$(pgrep -P "$p" 2>/dev/null || true)"
			[[ -n "$children" ]] && next="$next $children"
		done
		pids="$pids $next"
		frontier="$next"
	done
	local sum=0 rss p
	for p in $pids; do
		rss="$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' ')"
		[[ -n "$rss" ]] && sum=$((sum + rss))
	done
	echo "$sum"
}

cmd_mem() {
	if ! tmux ls 2>/dev/null | grep -q .; then
		echo "no tmux sessions"
		return
	fi
	printf '%-20s %10s %6s\n' SESSION RSS_MB PANES
	local session pid panes total rss
	while IFS= read -r session; do
		[[ -z "$session" ]] && continue
		total=0; panes=0
		while IFS= read -r pid; do
			[[ -z "$pid" ]] && continue
			panes=$((panes + 1))
			rss="$(pstree_rss "$pid")"
			total=$((total + rss))
		done < <(tmux list-panes -s -t "$session" -F '#{pane_pid}' 2>/dev/null)
		printf '%-20s %10s %6s\n' "$session" "$((total / 1024))" "$panes"
	done < <(tmux ls -F '#{session_name}' 2>/dev/null)
}

cmd_kill() {
	local name="${1:-}"
	[[ -n "$name" ]] || die "usage: autovim kill <name>"
	if ! session_exists "$name"; then
		die "no live session: $name"
	fi
	tmux kill-session -t "$name"
	log "killed: $name"
}

cmd_attach() {
	local name="$1"
	local dir
	dir="$(get_dir "$name")" || die "no such workspace: $name (try 'autovim new' or 'autovim ls')"

	if session_exists "$name"; then
		attach_or_switch "$name"
		return
	fi

	[[ -d "$dir" ]] || die "workspace directory missing: $dir (edit with: autovim edit $name)"

	tmux new-session -d -s "$name" -c "$dir"
	tmux send-keys -t "$name" 'nvim .' C-m
	attach_or_switch "$name"
}

usage() {
	cat <<EOF
autovim — tmux + nvim workspace manager

usage:
  autovim new                    create a workspace (prompts)
  autovim <name>                 attach or start workspace
  autovim edit <name>            edit a workspace (prompts; blank keeps current)
  autovim rm <name>              remove workspace + kill its session if alive
  autovim ls                     list workspaces and session status
  autovim mem                    RSS per live tmux session
  autovim kill <name>            kill a session (workspace entry kept)

config:
  $CONFIG_FILE
EOF
}

main() {
	ensure_config
	case "${1:-}" in
		'')                    usage; exit 0 ;;
		-h|--help|help)        usage ;;
		new)                   require_tmux; cmd_new ;;
		edit)                  require_tmux; shift; cmd_edit "${1:-}" ;;
		rm)                    require_tmux; shift; cmd_rm "${1:-}" ;;
		ls)                    require_tmux; cmd_ls ;;
		mem|meme)              require_tmux; cmd_mem ;;
		kill)                  require_tmux; shift; cmd_kill "${1:-}" ;;
		*)                     require_tmux; cmd_attach "$1" ;;
	esac
}

main "$@"