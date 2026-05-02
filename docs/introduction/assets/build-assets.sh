#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="$ROOT/images"
GIF="$ROOT/gifs"
TMP="$ROOT/.tmp"

mkdir -p "$IMG" "$GIF" "$TMP"

font="Adwaita-Sans"
mono="Adwaita-Mono"

make_svg() {
  local out="$1"
  local title="$2"
  local accent="$3"
  local body="$4"
  magick -size 1440x900 xc:"#111318" \
    -fill "#171b22" -draw "roundrectangle 40,38 1400,862 18,18" \
    -fill "#222833" -draw "roundrectangle 64,68 1376,128 12,12" \
    -fill "$accent" -draw "roundrectangle 84,84 132,112 8,8" \
    -fill "#f3f6fb" -font "$font" -pointsize 34 -annotate +152+109 "$title" \
    -fill "#8a94a6" -font "$mono" -pointsize 20 -annotate +1110+109 "AutoVim" \
    -fill "#0d1016" -draw "roundrectangle 72,154 1010,828 12,12" \
    -fill "#151a22" -draw "roundrectangle 1032,154 1368,828 12,12" \
    -fill "#263140" -draw "rectangle 72,154 1010,202" \
    -fill "#263140" -draw "rectangle 1032,154 1368,202" \
    -fill "#e8edf6" -font "$mono" -pointsize 22 -annotate +96+186 "$body" \
    -fill "#a9b4c7" -font "$mono" -pointsize 20 -annotate +1056+186 "panel / status" \
    "$out"
}

panel_lines() {
  local file="$1"
  shift
  local y=242
  local color
  for line in "$@"; do
    color="#d6deeb"
    case "$line" in
      *"DONE"*|*"ready"*|*"synced"*|*"running"*) color="#9be9a8" ;;
      *"WARN"*|*"drift"*|*"waiting"*) color="#ffd580" ;;
      *"ERR"*|*"blocked"*) color="#ff7b72" ;;
      *"cmd:"*|*"key:"*) color="#7dd3fc" ;;
    esac
    magick "$file" -fill "$color" -font "$mono" -pointsize 22 -annotate +1060+"$y" "$line" "$file"
    y=$((y + 44))
  done
}

make_overview() {
  local out="$IMG/autovim-overview.png"
  make_svg "$out" "AutoVim workspace" "#7dd3fc" "editor: docs/introduction/README.md"
  magick "$out" \
    -fill "#1d2530" -draw "roundrectangle 100,240 444,388 12,12" \
    -fill "#1d2530" -draw "roundrectangle 472,240 816,388 12,12" \
    -fill "#1d2530" -draw "roundrectangle 100,428 444,576 12,12" \
    -fill "#1d2530" -draw "roundrectangle 472,428 816,576 12,12" \
    -fill "#1d2530" -draw "roundrectangle 100,616 816,780 12,12" \
    -fill "#f3f6fb" -font "$font" -pointsize 27 -annotate +128+286 "multi-repo root" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +128+326 "<leader>gw -> worktree" \
    -fill "#f3f6fb" -font "$font" -pointsize 27 -annotate +500+286 "gitsgraph" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +500+326 "<leader>gt -> graph" \
    -fill "#f3f6fb" -font "$font" -pointsize 27 -annotate +128+474 "auto-agents" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +128+514 "slots 0..9 + T1..T4" \
    -fill "#f3f6fb" -font "$font" -pointsize 27 -annotate +500+474 "typed KB" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +500+514 "shared/private/isolated" \
    -fill "#f3f6fb" -font "$font" -pointsize 27 -annotate +128+668 "debug, HTTP, docs, remote sync" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +128+708 "Go + .http + Markdown + rsync" \
    "$out"
  panel_lines "$out" "1: jarvis working" "2: lector idle" "6: review float" "T2: tests running" "KB: shared ready"
}

make_worktree() {
  local out="$IMG/worktree-switcher.png"
  make_svg "$out" "worktree.nvim" "#9be9a8" "picker: <leader>gw"
  magick "$out" \
    -fill "#1d2530" -draw "roundrectangle 112,244 886,738 12,12" \
    -fill "#7dd3fc" -font "$font" -pointsize 30 -annotate +144+296 "Worktrees under ~/Source/Projects" \
    -fill "#e8edf6" -font "$mono" -pointsize 24 -annotate +152+354 "> autovim/main        branch main" \
    -fill "#a9b4c7" -font "$mono" -pointsize 24 -annotate +152+404 "  autovim/omarchy     branch omarchy" \
    -fill "#a9b4c7" -font "$mono" -pointsize 24 -annotate +152+454 "  plugins/auto-agents branch main" \
    -fill "#a9b4c7" -font "$mono" -pointsize 24 -annotate +152+504 "  plugins/gitsgraph   branch feature/ui" \
    -fill "#ffd580" -font "$mono" -pointsize 22 -annotate +152+594 "switch: save session -> :cd -> restart LSP" \
    -fill "#9be9a8" -font "$mono" -pointsize 22 -annotate +152+642 "safe remove checks disk + unsaved buffers" \
    "$out"
  panel_lines "$out" "cmd: WorktreePick" "cwd: autovim/omarchy" "LSP: gopls restarted" "session: restored" "neo-tree: re-rooted"
}

make_gitsgraph() {
  local out="$IMG/gitsgraph-dashboard.png"
  make_svg "$out" "gitsgraph.nvim" "#c084fc" "graph: <leader>gt"
  magick "$out" \
    -fill "#1d2530" -draw "roundrectangle 100,240 330,760 10,10" \
    -fill "#10151d" -draw "roundrectangle 356,240 650,760 10,10" \
    -fill "#1d2530" -draw "roundrectangle 676,240 910,760 10,10" \
    -fill "#7dd3fc" -font "$mono" -pointsize 22 -annotate +124+290 "Repos (4)" \
    -fill "#f3f6fb" -font "$mono" -pointsize 22 -annotate +124+342 "> [1] autovim" \
    -fill "#a9b4c7" -font "$mono" -pointsize 22 -annotate +124+390 "  [2] agents" \
    -fill "#a9b4c7" -font "$mono" -pointsize 22 -annotate +124+438 "  [3] gitsgraph" \
    -fill "#a9b4c7" -font "$mono" -pointsize 22 -annotate +124+486 "  [4] worktree (bare)" \
    -fill "#9be9a8" -font "$mono" -pointsize 24 -annotate +382+302 "* a1b2c3 intro docs" \
    -fill "#a9b4c7" -font "$mono" -pointsize 24 -annotate +382+354 "| * d4e5f6 agent kb" \
    -fill "#a9b4c7" -font "$mono" -pointsize 24 -annotate +382+406 "|/ 78c901 graph root" \
    -fill "#ffd580" -font "$mono" -pointsize 24 -annotate +382+458 "* 2468ac remote sync" \
    -fill "#f3f6fb" -font "$mono" -pointsize 20 -annotate +704+292 "commit a1b2c3" \
    -fill "#a9b4c7" -font "$mono" -pointsize 20 -annotate +704+338 "Author: johno" \
    -fill "#a9b4c7" -font "$mono" -pointsize 20 -annotate +704+384 "intro | 220 +" \
    -fill "#a9b4c7" -font "$mono" -pointsize 20 -annotate +704+430 "gifs  | 8 files" \
    "$out"
  panel_lines "$out" "1-9: select repo" "Enter: diff float" "f/F: fetch" "r: rescan" "dedupe: common git dir"
}

make_agents() {
  local out="$IMG/auto-agents-panel.png"
  make_svg "$out" "auto-agents.nvim" "#7dd3fc" "panel: <F5>    dock: <F6>"
  magick "$out" \
    -fill "#10151d" -draw "roundrectangle 96,238 912,782 12,12" \
    -fill "#263140" -draw "rectangle 96,238 912,288" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +126+272 "0 admin | 1 +jarvis | 2 lector | 3 shell | 6 float" \
    -fill "#9be9a8" -font "$mono" -pointsize 23 -annotate +126+344 "slot 1 claude/main     kb_scope=shared" \
    -fill "#7dd3fc" -font "$mono" -pointsize 23 -annotate +126+394 "slot 2 codex/lector    role=reviewer" \
    -fill "#ffd580" -font "$mono" -pointsize 23 -annotate +126+444 "slot 6 generic/review  manager=1" \
    -fill "#a9b4c7" -font "$mono" -pointsize 23 -annotate +126+520 "T1 shell   T2 tests running   T3 server   T4 scratch" \
    -fill "#c084fc" -font "$mono" -pointsize 23 -annotate +126+596 "KB root: .auto-agents-config/kb" \
    -fill "#a9b4c7" -font "$mono" -pointsize 23 -annotate +126+646 "shared -> private -> isolated scopes" \
    "$out"
  panel_lines "$out" "status: working" "kb: coding/shared" "model: persisted" "grants: src/, docs/" "dock: 0..9 + editor"
}

make_admin() {
  local out="$IMG/admin-panel.png"
  make_svg "$out" "admin slot 0" "#ffd580" "auto-agents://admin"
  magick "$out" \
    -fill "#10151d" -draw "roundrectangle 96,238 912,782 12,12" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +126+296 "> status" \
    -fill "#a9b4c7" -font "$mono" -pointsize 23 -annotate +126+344 "1 claude/main     running [2 tasks]" \
    -fill "#a9b4c7" -font "$mono" -pointsize 23 -annotate +126+392 "2 codex/lector    idle" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +126+472 "> agent mem" \
    -fill "#9be9a8" -font "$mono" -pointsize 23 -annotate +126+520 "slot 1  418 MB    slot 2  306 MB" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +126+600 "> kb sync -- manifest + wikilink lint" \
    -fill "#7dd3fc" -font "$mono" -pointsize 23 -annotate +126+672 "> resource grant 2 docs/introduction" \
    "$out"
  panel_lines "$out" "agent kill/restart" "kb init/sync/scope" "resource grant/cwd" "config show/path" "project import/list"
}

make_remote() {
  local out="$IMG/remote-sync.png"
  make_svg "$out" "remote-sync.nvim" "#9be9a8" "remote mirror workflow"
  magick "$out" \
    -fill "#1d2530" -draw "roundrectangle 122,270 850,705 14,14" \
    -fill "#f3f6fb" -font "$mono" -pointsize 25 -annotate +160+330 "<leader>rp  pull remote -> local mirror" \
    -fill "#a9b4c7" -font "$mono" -pointsize 22 -annotate +188+382 "rsync + snapshot commit becomes HEAD" \
    -fill "#ffd580" -font "$mono" -pointsize 25 -annotate +160+466 "<leader>rd  drift report" \
    -fill "#a9b4c7" -font "$mono" -pointsize 22 -annotate +188+518 "compare remote against git HEAD" \
    -fill "#9be9a8" -font "$mono" -pointsize 25 -annotate +160+602 "<leader>rs  drift-gated push" \
    -fill "#a9b4c7" -font "$mono" -pointsize 22 -annotate +188+654 "pre-push snapshot + quiet pull after" \
    "$out"
  panel_lines "$out" "config: .autovim-remote.json" "pull: synced" "drift: clean" "push: gated" "log: <leader>rl"
}

make_gobugger() {
  local out="$IMG/gobugger-debugger.png"
  make_svg "$out" "gobugger.nvim" "#ff7b72" "Go debug workflow"
  magick "$out" \
    -fill "#10151d" -draw "roundrectangle 100,238 910,780 12,12" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +132+302 "func TestInvoiceWorkflow(t *testing.T) {" \
    -fill "#ff7b72" -font "$mono" -pointsize 23 -annotate +132+350 "  breakpoint -> service.Process(ctx, req)" \
    -fill "#a9b4c7" -font "$mono" -pointsize 23 -annotate +132+398 "}" \
    -fill "#263140" -draw "roundrectangle 132,480 860,708 10,10" \
    -fill "#7dd3fc" -font "$mono" -pointsize 23 -annotate +164+536 "<leader>dt debug test under cursor" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +164+588 "launch.json + envFile + buildFlags" \
    -fill "#9be9a8" -font "$mono" -pointsize 21 -annotate +164+640 "dap-view opens variables, stack, watches" \
    "$out"
  panel_lines "$out" "F9 continue" "F8 step over" "doctor: <leader>dD" "last error: <leader>dE" "delve: mason-managed"
}

make_md() {
  local out="$IMG/md-harpoon.png"
  make_svg "$out" "md-harpoon.nvim" "#c084fc" "six markdown render slots"
  magick "$out" \
    -fill "#1d2530" -draw "roundrectangle 120,246 360,430 10,10" \
    -fill "#1d2530" -draw "roundrectangle 390,246 630,430 10,10" \
    -fill "#1d2530" -draw "roundrectangle 660,246 900,430 10,10" \
    -fill "#10151d" -draw "roundrectangle 180,486 420,670 10,10" \
    -fill "#10151d" -draw "roundrectangle 450,486 690,670 10,10" \
    -fill "#10151d" -draw "roundrectangle 720,486 960,670 10,10" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +150+312 "slot 1" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +420+312 "slot 2" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +690+312 "slot 3" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +210+552 "slot a" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +480+552 "slot s" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +750+552 "slot d" \
    "$out"
  panel_lines "$out" "<leader>m1..m3" "<leader>ma/ms/md" "find: <leader>mf" "browser: <leader>mb" "render: md-render"
}

make_kulala() {
  local out="$IMG/kulala-http.png"
  make_svg "$out" "kulala.nvim" "#7dd3fc" "HTTP collections"
  magick "$out" \
    -fill "#10151d" -draw "roundrectangle 104,238 914,780 12,12" \
    -fill "#f3f6fb" -font "$mono" -pointsize 23 -annotate +136+304 "GET {{BASE_URL}}/v1/releases" \
    -fill "#a9b4c7" -font "$mono" -pointsize 23 -annotate +136+354 "Authorization: Bearer {{API_KEY}}" \
    -fill "#7dd3fc" -font "$mono" -pointsize 23 -annotate +136+452 "<leader>Rs scaffold .rest/" \
    -fill "#9be9a8" -font "$mono" -pointsize 23 -annotate +136+502 "<leader>Rr run request" \
    -fill "#ffd580" -font "$mono" -pointsize 23 -annotate +136+552 "<leader>Re select env" \
    -fill "#a9b4c7" -font "$mono" -pointsize 21 -annotate +136+638 "private env file stays gitignored" \
    "$out"
  panel_lines "$out" "view: body" "env: dev" "replay: <leader>Rl" "run all: <leader>Ra" "scratch: <leader>Rn"
}

make_gif() {
  local name="$1"
  local title="$2"
  local accent="$3"
  shift 3
  local frames=()
  local i=0
  for step in "$@"; do
    local frame="$TMP/${name}-${i}.png"
    make_svg "$frame" "$title" "$accent" "$step"
    magick "$frame" \
      -fill "#1d2530" -draw "roundrectangle 120,290 910,690 16,16" \
      -fill "$accent" -font "$font" -pointsize 34 -annotate +160+370 "$step" \
      -fill "#a9b4c7" -font "$mono" -pointsize 24 -annotate +160+440 "command flow shown as a product storyboard" \
      -fill "#f3f6fb" -font "$mono" -pointsize 24 -annotate +160+512 "frame $((i + 1)) of $#" \
      "$frame"
    panel_lines "$frame" "step: $((i + 1))/$#" "status: running" "KB: persistent" "cwd: stable" "ready"
    frames+=("$frame")
    i=$((i + 1))
  done
  magick -delay 90 -loop 0 "${frames[@]}" "$GIF/${name}.gif"
}

make_overview
make_worktree
make_gitsgraph
make_agents
make_admin
make_remote
make_gobugger
make_md
make_kulala

make_gif "worktree-switch" "worktree.nvim" "#9be9a8" \
  "open picker: <leader>gw" \
  "select feature worktree" \
  "session + LSP re-anchor"

make_gif "gitsgraph-browse" "gitsgraph.nvim" "#c084fc" \
  "open dashboard: <leader>gt" \
  "select repo 2" \
  "press Enter for diff"

make_gif "auto-agents-orchestration" "auto-agents.nvim" "#7dd3fc" \
  "focus slot 1: <leader>a1" \
  "delegate review to slot 6" \
  "shared KB records result"

make_gif "admin-panel" "admin slot 0" "#ffd580" \
  "agent mem" \
  "kb sync" \
  "resource grant 2 docs/"

make_gif "remote-sync" "remote-sync.nvim" "#9be9a8" \
  "pull remote: <leader>rp" \
  "check drift: <leader>rd" \
  "push safely: <leader>rs"

make_gif "gobugger" "gobugger.nvim" "#ff7b72" \
  "set breakpoint" \
  "debug test: <leader>dt" \
  "inspect dap-view"

make_gif "md-harpoon" "md-harpoon.nvim" "#c084fc" \
  "render slot 1" \
  "render slot a" \
  "restore six docs"

make_gif "kulala" "kulala.nvim" "#7dd3fc" \
  "scaffold .rest/" \
  "run request" \
  "replay last response"

rm -rf "$TMP"

echo "Generated introduction assets in $IMG and $GIF"
