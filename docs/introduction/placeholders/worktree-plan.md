# Worktree Capture Plan
**Tags:** repo:autovim area:introduction type:reference owner:shared
**Abstract:** A short sample plan for live screenshots of AutoVim's worktree, Git graph, and agent workflows.

## Scenario

The workspace has several related checkouts:

```text
~/Source/Projects/
  autovim/
    .git/
    main/
    omarchy/
    docs-intro/
  nvim-plugins/
    auto-agents.nvim/
    gitsgraph.nvim/
    worktree.nvim/
```

## Capture Steps

1. Use `<leader>gw` to show worktree switching.
2. Use `<leader>gt` to show the multi-repo Git graph.
3. Use `<F5>` to show the auto-agent panel.
4. In slot 0, run `status`, `agent mem`, `kb sync`, and `resource list`.
5. Use `<F6>` to show the navigation dock.

## Nice-To-Have Panels

- A Go file with a visible breakpoint for `gobugger.nvim`.
- A `.http` buffer with a selected request for `kulala.nvim`.
- A Markdown render pane showing this document.
