-- md-harpoon.nvim — keymap spec.
--
-- Plugin source: github.com/yongjohnlee80/md-harpoon.nvim. Local working
-- copy lives at ~/Source/Projects/nvim-plugins/md-harpoon.nvim for
-- development. To work against the local copy temporarily, swap the
-- spec line below for `dir = vim.fn.expand("~/Source/Projects/nvim-plugins/md-harpoon.nvim")`
-- + `name = "md-harpoon.nvim"` — lazy will use it instead of fetching.
--
-- md-harpoon is a six-slot manager built on top of `delphinus/md-render.nvim`.
-- md-render does the actual rendering (tables, callouts, fenced code,
-- inline images / video / Mermaid via Kitty graphics protocol); md-harpoon
-- adds the multi-float layout and cursor-position memory. md-render is
-- declared as a `dependencies` entry below so it loads alongside.
--
-- Layout: 1/2/3 at the top, a/s/d cascaded half-a-column right and a few
-- rows down of their pair. All six panels share the same height; overlap
-- is intentional. The top row uses digits (1/2/3) instead of q/w/e to
-- avoid colliding with vim's macro-record key.

local function slot_focus(slot)
  return function() require("md-harpoon").focus(slot) end
end

local function slot_render(slot)
  return function() require("md-harpoon").render_current(slot) end
end

return {
  {
    "yongjohnlee80/md-harpoon.nvim",
    tag = "v0.1.1",
    dependencies = {
      { "delphinus/md-render.nvim", version = "*" },
    },
    ft = { "markdown", "markdown.mdx" },
    cmd = {
      "MdHarpoonFocus", "MdHarpoonRender", "MdHarpoonRenderPath",
      "MdHarpoonFind", "MdHarpoonCloseAll",
      "MdRender", "MdRenderTab", "MdRenderPager",
    },
    keys = {
      -- Digits + home row — the frequent action. Three behaviors collapsed
      -- into one keystroke:
      --   * float open  → focus (jump cursor into the slot)
      --   * float closed, slot has remembered source → reopen + restore
      --     cursor to where you left it
      --   * slot never rendered → render the current buffer
      -- Fallback in case 3 means first-time use just works without having
      -- to remember the shifted variant.
      { "<leader>m1", slot_focus("1"), desc = "Markdown: upper left (1) — focus / open"   },
      { "<leader>m2", slot_focus("2"), desc = "Markdown: upper middle (2) — focus / open" },
      { "<leader>m3", slot_focus("3"), desc = "Markdown: upper right (3) — focus / open"  },
      { "<leader>ma", slot_focus("a"), desc = "Markdown: left (a) — focus / open"         },
      { "<leader>ms", slot_focus("s"), desc = "Markdown: middle (s) — focus / open"       },
      { "<leader>md", slot_focus("d"), desc = "Markdown: right (d) — focus / open"        },
      -- Shifted digits / uppercase — explicit "render current buffer into
      -- this slot". Cursor resets to the top (fresh load by definition).
      { "<leader>m!", slot_render("1"), desc = "Markdown: upper left (1) — render current"   },
      { "<leader>m@", slot_render("2"), desc = "Markdown: upper middle (2) — render current" },
      { "<leader>m#", slot_render("3"), desc = "Markdown: upper right (3) — render current"  },
      { "<leader>mA", slot_render("a"), desc = "Markdown: left (a) — render current"         },
      { "<leader>mS", slot_render("s"), desc = "Markdown: middle (s) — render current"       },
      { "<leader>mD", slot_render("d"), desc = "Markdown: right (d) — render current"        },
      -- Fuzzy-find a markdown file under cwd → vim.ui.select panel prompt
      -- → render. Uses Snacks.picker.files when available; falls back to
      -- glob + ui.select otherwise. Panel prompt shows human-readable
      -- labels ("upper left (1)" / "left (a)" / …).
      { "<leader>mf", function() require("md-harpoon").find() end,
        desc = "Markdown: find file under cwd → pick panel" },
      -- Close every visible float. Sources + cursor positions are kept,
      -- so any digit / lowercase key brings the slot back where it was.
      { "<leader>mc", function() require("md-harpoon").close_all() end,
        desc = "Markdown: close all md-harpoon floats" },
      -- Tab preview — provided by upstream md-render. md-render loads as a
      -- dep alongside md-harpoon, so the <Plug> map is live by the time
      -- this keymap fires.
      { "<leader>mt", "<Plug>(md-render-preview-tab)", desc = "Markdown: Preview (tab)" },
    },
  },
}
