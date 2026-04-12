# Johno's Neovim Config

My Neovim configuration for [Omarchy](https://omarchy.com), purpose-built for TypeScript and Go development with Claude as a first-class citizen.

## Why This Exists

Some people meditate. Some do yoga. I open Neovim, fire up Claude, and write Go and TypeScript until the world makes sense again. This is my happy place -- a terminal where keystrokes are cheap, feedback loops are tight, and the AI pair programmer never judges my variable names.

There's a certain poetry to it: Go for when you want the compiler to hold your hand, TypeScript for when you want the type system to argue with you, and Claude for when you want someone to tell you that your approach is "interesting" before gently suggesting you rewrite the whole thing. Neovim ties it all together like the world's most opinionated glue.

I've tried other setups. I've clicked through menus. I've dragged and dropped. I've used mice like some kind of animal. But nothing beats the flow of modal editing, instant AI assistance, and a config that loads faster than you can say "VS Code is updating." If the terminal is home, this config is the furniture.

## What's Inside

- **[LazyVim](https://www.lazyvim.org/)** -- because life's too short to configure everything from scratch, but too long to use someone else's config without tweaking it
- **[claudecode.nvim](https://github.com/anthropics/claude-code/tree/main/packages/claudecode.nvim)** -- Claude Code integration, right in the editor. `<leader>ac` and you're pair programming with an AI that actually reads your code
- **LSP + Mason** -- language servers managed properly, so Go and TypeScript just work
- **Treesitter** -- syntax highlighting that understands your code, not just your brackets
- **11 colorschemes** -- because choosing a theme is a form of self-expression (currently rotating through them like outfits)

## Key Bindings Worth Knowing

| Binding | What It Does |
|---|---|
| `jk` | Escape insert mode (the only correct mapping) |
| `<leader>ac` | Toggle Claude Code |
| `<leader>as` | Send selection to Claude |
| `<leader>ab` | Add current buffer to Claude |
| `<leader>aa` | Accept Claude's diff |
| `<leader>ad` | Deny Claude's diff |

## The Stack

```
Neovim + LazyVim
├── Go (the language that says "no" so you don't have to)
├── TypeScript (the language that says "any" when you give up)
└── Claude (the AI that says "have you considered..." before saving your afternoon)
```

## License

[MIT](LICENSE) -- take what you want, blame no one.
