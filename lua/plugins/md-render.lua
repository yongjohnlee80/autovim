-- md-render.nvim — terminal-native Markdown previewer with rich layout
-- (tables, callouts, fenced code with TS highlighting, inline images/video,
-- Mermaid, OSC 8 links). Renders into a separate float / tab / pager
-- window; the editing buffer stays untouched.
--
-- Terminal compatibility (team note):
--   * Ghostty / Kitty / WezTerm   — fully verified by upstream; images,
--     video, and Mermaid all work.
--   * iTerm2                      — NOT in upstream's verified list. Text
--     rendering (tables, callouts, code blocks, OSC 8 links) is fine in
--     any modern terminal. Inline images / video / Mermaid rely on the
--     Kitty graphics protocol; iTerm2 3.5+ has partial support but the
--     plugin author hasn't validated it.
--
-- Three independent preview slots — a / s / d for left / middle / right —
-- so the user can compare up to three markdown files side-by-side. The
-- slot manager is in `lua/utils/md_render.lua`; see that file for why
-- it exists (the bundled `MdPreview.show()` only supports one float at a
-- time).
--
-- Keymaps are intentionally NOT filetype-restricted. The slot manager
-- notifies the user when the current buffer isn't markdown — with `ft =
-- "markdown"` on the keymap, that warning would never be reachable
-- (the keymap simply wouldn't exist on the wrong filetype, leaving the
-- user staring at silence wondering why the keystroke did nothing).
local function slot_focus(slot)
  return function() require("utils.md_render").focus(slot) end
end

local function slot_render(slot)
  return function() require("utils.md_render").render_current(slot) end
end

return {
  {
    "delphinus/md-render.nvim",
    version = "*",
    ft = { "markdown", "markdown.mdx" },
    cmd = { "MdRender", "MdRenderTab", "MdRenderPager" },
    keys = {
      -- Lowercase — the frequent action. Three behaviors collapsed
      -- into one key:
      --   * float open  → focus (jump cursor into the slot)
      --   * float closed, slot has last doc → reopen it
      --   * slot never rendered → render the current buffer
      -- The fallback in case 3 means first-time use just works without
      -- having to remember the uppercase variant.
      { "<leader>ma", slot_focus("a"), desc = "Markdown: Slot a (left) — focus / open" },
      { "<leader>ms", slot_focus("s"), desc = "Markdown: Slot s (middle) — focus / open" },
      { "<leader>md", slot_focus("d"), desc = "Markdown: Slot d (right) — focus / open" },
      -- Uppercase — explicit "render current buffer into this slot".
      -- Use this to swap a slot's content to whatever buffer you're in.
      { "<leader>mA", slot_render("a"), desc = "Markdown: Slot a (left) — render current" },
      { "<leader>mS", slot_render("s"), desc = "Markdown: Slot s (middle) — render current" },
      { "<leader>mD", slot_render("d"), desc = "Markdown: Slot d (right) — render current" },
      -- Tab preview (full-screen, plugin-default behavior). The plugin's
      -- show_tab() does its own non-markdown notify, so leaving this
      -- ft-unrestricted is consistent with the slot keymaps.
      { "<leader>mt", "<Plug>(md-render-preview-tab)", desc = "Markdown: Preview (tab)" },
    },
  },
}
