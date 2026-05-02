# Introduction Assets
**Tags:** repo:autovim area:introduction type:reference owner:shared living-doc
**Abstract:** Asset manifest for the AutoVim introduction document, including generated screenshot-style PNGs, animated GIF demos, and the generator command.

- **Parent doc:** [../README.md](../README.md)
- **Generator:** [build-assets.sh](build-assets.sh)
- **Static images:** `images/*.png`
- **Animated demos:** `gifs/*.gif`

## Generated Files

| Asset | Purpose |
|---|---|
| `images/autovim-overview.png` | First-viewport overview of editor, worktrees, Git graph, agents, and KB. |
| `images/worktree-switcher.png` | Worktree picker and session/LSP behavior. |
| `images/gitsgraph-dashboard.png` | Multi-repo Git graph with picker, graph, and preview panes. |
| `images/auto-agents-panel.png` | Main auto-agent panel with admin, agents, floats, and KB. |
| `images/admin-panel.png` | Admin REPL command surface. |
| `images/remote-sync.png` | Remote-sync pull, drift, push workflow. |
| `images/gobugger-debugger.png` | Go debug workflow built around launch.json and dap-view. |
| `images/md-harpoon.png` | Six Markdown render panes. |
| `images/kulala-http.png` | `.rest/` HTTP request workflow. |
| `gifs/worktree-switch.gif` | Animated worktree switch storyboard. |
| `gifs/gitsgraph-browse.gif` | Animated repo/commit selection storyboard. |
| `gifs/auto-agents-orchestration.gif` | Animated agent orchestration storyboard. |
| `gifs/admin-panel.gif` | Animated admin command flow. |
| `gifs/remote-sync.gif` | Animated remote sync workflow. |
| `gifs/gobugger.gif` | Animated debug workflow. |
| `gifs/md-harpoon.gif` | Animated Markdown pane workflow. |
| `gifs/kulala.gif` | Animated HTTP collection workflow. |

## Regenerate

Run from the repo root:

```bash
docs/introduction/assets/build-assets.sh
```

The generated images are intentionally committed so the introduction renders without extra tooling. The script requires ImageMagick with SVG support.

## Notes

These are illustrative visual aids rather than live interactive screenshots. They use the same commands, labels, and workflows documented in the introduction and are suitable for a first-pass product overview. For live screenshots, open the placeholder files in `../placeholders/`, run the plugin commands in Neovim, and replace the generated PNGs/GIFs with captured terminal images.
