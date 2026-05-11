# AutoVim Custom Layer — starter templates

This directory ships with AutoVim as **starter templates**. Copy it into
the gitignored override location once and start editing:

```sh
cp -r docs/custom-example ~/.config/nvim/lua/custom
```

(The `install.sh` installer does this automatically on a fresh install,
so most users land with `lua/custom/` already populated.)

## Layout

```
lua/custom/                        ← gitignored; not touched by `update.sh`
├── init.lua                       ← entrypoint; sourced LAST after config/*
├── options.lua                    ← your vim.opt.* overrides
├── keymaps.lua                    ← your keymap overrides / additions
├── autocmds.lua                   ← your autocmds
├── plugins/                       ← extra / overriding lazy specs
│   └── example.lua
└── utils/                         ← helpers; require("custom.utils.foo")
```

## Load order

```
1. lua/config/options.lua         (stock)
2. lua/config/keymaps.lua         (stock)
3. lua/config/autocmds.lua        (stock)
4. lazy.setup → resolves plugin specs
   - LazyVim plugins
   - lua/plugins/* (stock AutoVim)
   - lua/custom/plugins/* (yours — merges by repo name)
5. lua/custom/init.lua            (yours)
```

Because your `init.lua` runs last, scalar overrides win:

```lua
-- options.lua (stock)
vim.opt.relativenumber = true

-- custom/options.lua
vim.opt.relativenumber = false   -- wins
```

## Overriding a stock plugin

lazy.nvim merges specs by **repo name**. To tweak `opts` on an existing
plugin without touching the stock spec:

```lua
-- lua/custom/plugins/auto-agents-overrides.lua
return {
  {
    "yongjohnlee80/auto-agents",
    opts = {
      panel = { slot_count = 8 },
    },
  },
}
```

To disable a stock plugin entirely:

```lua
return {
  { "yongjohnlee80/gobugger", enabled = false },
}
```

To override a plugin's keymaps:

```lua
return {
  {
    "yongjohnlee80/auto-agents",
    keys = {
      { "<F5>", false },                                      -- drop the stock binding
      { "<leader>aa", "<cmd>AutoAgents<cr>", desc = "Agents" }, -- new one
    },
  },
}
```

## Updating AutoVim

```sh
~/.config/nvim/update.sh
```

The updater:

- Fetches the latest AutoVim tree and overlays the **tracked files only**.
- Never touches `lua/custom/` (gitignored upstream, so not in the overlay).
- Never touches the user's `.git/` (you can fork AutoVim and keep your
  own remote — survives every update).
- Then runs `Lazy! sync` so the lockfile bump pulls fresh plugin
  versions.

If you've forked AutoVim and configured your own `origin`, after
`update.sh` your working tree will show the updated stock files as
uncommitted changes against your fork — commit them, rebase, or
`git reset --hard origin/main` as you prefer.
