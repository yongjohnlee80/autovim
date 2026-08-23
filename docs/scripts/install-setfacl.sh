#!/usr/bin/env bash
# install-setfacl.sh — install POSIX ACL tooling on a Debian/Ubuntu remote.
#
# Prerequisite for the `grant-acl` command in remote-sync.nvim's commands
# array (see ~/Source/Documents/knowledge-base/raw/autovim/troubleshoot/
# 2026-04-27-rsync-permission-denied-on-system-dirs.md). On minimal Ubuntu
# images the `setfacl` binary is NOT preinstalled — it ships in the `acl`
# package. Run this once per VM before the first `<leader>rc` → grant-acl
# invocation.
#
# Usage (on the remote VM):
#   curl -fsSL <url-or-scp> | sudo bash
#   # or:
#   chmod +x install-setfacl.sh && sudo ./install-setfacl.sh
#
# Idempotent: safe to re-run. Exits non-zero on:
#   - non-Debian/Ubuntu host (no apt-get available)
#   - apt-get install failure
#   - filesystem actively rejecting ACLs (mounted with `noacl`)
#
# Requires sudo (apt-get + getfacl on a system path). On NOPASSWD-sudo
# remotes, runs unattended; otherwise it'll prompt for the user's password.

set -euo pipefail

ACL_PROBE_PATH="${1:-/}"   # override to probe a specific tree, e.g. /etc/ddex-sftp

# ── 1. apt-get must exist ─────────────────────────────────────────────
if ! command -v apt-get >/dev/null 2>&1; then
  echo "install-setfacl: apt-get not found. This script targets Debian/Ubuntu." >&2
  echo "                 On RHEL/Fedora: dnf install acl   ;   on Alpine: apk add acl" >&2
  exit 1
fi

# ── 2. install acl (idempotent) ───────────────────────────────────────
if command -v setfacl >/dev/null 2>&1; then
  echo "install-setfacl: setfacl already present at $(command -v setfacl)"
else
  echo "install-setfacl: installing acl package…"
  sudo apt-get update -qq
  sudo apt-get install -y acl
fi

setfacl --version | head -1

# ── 3. sanity-check the filesystem actually honors ACLs ───────────────
# `getfacl` on a path that doesn't support ACLs prints "Operation not
# supported"; on a working FS it prints a `# file:` block.
if ! getfacl --absolute-names "$ACL_PROBE_PATH" >/dev/null 2>&1; then
  echo "install-setfacl: getfacl failed on $ACL_PROBE_PATH — filesystem may not support ACLs." >&2
  echo "                 Check 'mount | grep \" $ACL_PROBE_PATH \"' for a 'noacl' option," >&2
  echo "                 then remount with: sudo mount -o remount,acl $ACL_PROBE_PATH" >&2
  exit 1
fi

echo "install-setfacl: ok — setfacl installed and ACLs are honored on ${ACL_PROBE_PATH}."
echo "install-setfacl: next step → run the 'grant-acl' command in your .autovim-remote.json"
echo "                 (or invoke <leader>rc from inside the project in nvim)."
