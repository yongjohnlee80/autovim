# Ghostty Notification Sound Is Too Quiet On Omarchy
**Tags:** `type:reference` `repo:nvim` `area:ghostty` `area:audio` `area:notifications` `owner:codex` `date-reviewed:2026-04-25`
**Abstract:** Troubleshooting notes for quiet notification sounds when using Ghostty on Omarchy/Arch Linux. The main finding is that the local Neovim notification sound path uses `pw-play`, not Ghostty's built-in bell, and Omarchy's theme include does not override any `bell-*` settings. The first fixes to try are explicit Ghostty bell settings or PipeWire per-stream volume adjustments.

- **Date:** 2026-04-25
- **Local files:** `~/.config/ghostty/config`, `~/.config/omarchy/current/theme/ghostty.conf`, `lua/utils/sound.lua`, `assets/sound/notification.wav`
- **Verified environment:** Ghostty `1.3.1-arch2` on GTK, Omarchy on Arch Linux

## Symptom

Notification sounds are loud and clear from other applications, but Ghostty and the Neovim notification path sound muffled or much quieter.

## What the local config is doing

The local Neovim sound helper lives in `lua/utils/sound.lua`.

- `DEFAULT_SOUND` points to `~/.config/nvim/assets/sound/notification.wav`
- on Linux it prefers `pw-play`, then `paplay`, then `aplay`
- playback is done with `vim.system({ r.cmd, path }, { detach = true })`

At the time of inspection, the sound helper existed on disk but no call site was found in the current repo snapshot that actually invokes `sound.ping()` or `sound.play(...)`.

## What Omarchy is and is not overriding

Ghostty loads `~/.config/omarchy/current/theme/ghostty.conf` through the top-level `~/.config/ghostty/config`.

The Omarchy theme include was checked and does not define:

- `bell-features`
- `bell-audio-path`
- `bell-audio-volume`

No `bell-*` settings were found under `~/.config` during the local search. That means the quiet bell is not explained by an Omarchy override in the checked config files.

## Likely causes

### 1. Ghostty audio bell is using defaults

Ghostty documents `bell-audio-volume` as a floating-point value from `0.0` to `1.0`, with a default of `0.5`. If `bell-features=audio` is enabled, half-volume is the expected default unless overridden.

### 2. Ghostty may be using the system bell path

Ghostty also supports `bell-features=system`, which delegates notification behavior to system settings instead of a Ghostty-specific audio file and volume. In that mode, the volume and sound characteristics are determined by the desktop/system bell configuration.

### 3. PipeWire may have a low remembered stream volume

Because the Neovim helper prefers `pw-play`, a quiet playback stream can also come from PipeWire stream volume rather than from Ghostty itself.

## Recommended fixes

### Make Ghostty explicit instead of relying on defaults

Add this to `~/.config/ghostty/config`:

```conf
bell-features = audio
bell-audio-path = ~/.config/nvim/assets/sound/notification.wav
bell-audio-volume = 1.0
```

This removes ambiguity between Ghostty's `audio` and `system` bell modes and bypasses the default `0.5` audio-bell volume.

### Check PipeWire per-stream volume while the sound is playing

If the sound is still quiet after setting Ghostty explicitly, inspect the active PipeWire stream and raise it:

```bash
wpctl status
wpctl get-volume <stream-id>
wpctl set-volume <stream-id> 1.0
```

This is especially relevant for the Neovim helper path because it prefers `pw-play`.

### Test the exact WAV path directly

Use the same file outside Neovim to isolate the problem:

```bash
pw-play ~/.config/nvim/assets/sound/notification.wav
```

If that is also quiet, the problem is likely in PipeWire stream volume or the target sink rather than in Neovim.

## Recommendations for the Neovim helper

- If the helper is intended to be the canonical notification path, wire `sound.ping()` into the actual notification event explicitly.
- If `pw-play` remains too quiet even with normal PipeWire stream volume, consider passing a volume flag when spawning it.
- If Ghostty bell and `pw-play` are both quiet, prioritize PipeWire stream inspection before changing Omarchy theme files.

## Sources

- Ghostty config reference: https://ghostty.org/docs/config/reference
- Ghostty release notes `1.2.0`: https://ghostty.org/docs/install/release-notes/1-2-0
- Arch manual for `ghostty(5)`: https://man.archlinux.org/man/ghostty.5.en
- Arch manual for `wpctl(1)`: https://man.archlinux.org/man/extra/wireplumber/wpctl.1.en
