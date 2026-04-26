-- Tiny audio-notification helper. `M.ping()` plays a short bell-ish sound;
-- `M.play(path)` plays an arbitrary file. Both are async (vim.system) so
-- they never block the UI, and silently no-op when no player is available
-- (headless nvim, ssh without audio forwarding, muted box, etc.) — the
-- caller shouldn't have to guard against environment.

local M = {}

-- Per-platform (player_cmd, default_ping_path). The first `player` whose
-- binary is on $PATH wins; we cache the result so we don't re-stat every
-- call. nil = no usable player on this system → ping/play become no-ops.
-- Bundled default lives in the config dir so the sound is consistent
-- across machines (no reliance on system theme files).
local DEFAULT_SOUND = vim.fn.stdpath("config") .. "/assets/sound/notification.wav"

local resolved
local function resolve()
  if resolved ~= nil then return resolved end

  local sysname = (vim.uv or vim.loop).os_uname().sysname

  local cmds
  if sysname == "Darwin" then
    cmds = { "afplay" }
  else
    -- Linux: prefer PipeWire's pw-play (Omarchy default), then PulseAudio
    -- paplay, then ALSA aplay. All three handle .wav.
    cmds = { "pw-play", "paplay", "aplay" }
  end

  for _, cmd in ipairs(cmds) do
    if vim.fn.executable(cmd) == 1 then
      resolved = { cmd = cmd, default = DEFAULT_SOUND }
      return resolved
    end
  end

  resolved = false
  return resolved
end

--- Play an arbitrary audio file. No-ops silently if no player is available
--- or the file doesn't exist.
---@param path string absolute path to a sound file the resolved player can decode
function M.play(path)
  local r = resolve()
  if not r then return end
  if vim.fn.filereadable(path) ~= 1 then return end
  vim.system({ r.cmd, path }, { detach = true })
end

--- Play the platform's default short notification sound.
function M.ping()
  local r = resolve()
  if not r then return end
  M.play(r.default)
end

return M
