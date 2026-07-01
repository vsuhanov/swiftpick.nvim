---@module "swiftpick.helper.emoji"

local emojis = {
  "🐱", "🐶", "🐰", "🦊", "🐼", "🐨", "🐸", "🦋", "🐝", "🐞",
  "🌸", "🌻", "🌺", "🍀", "🌈", "⭐", "🌙", "✨", "💎", "🎀",
  "🍓", "🍒", "🍑", "🫐", "🍉", "🧁", "🍩", "🍪", "🎂", "🍭",
  "🎨", "🎵", "🎈", "🪁", "🧸", "🦄", "🐙", "🦑", "🐡", "🦔",
  "🐿️", "🦩", "🐳", "🦜", "🐢", "🦎", "🪲", "🐌", "🦕", "🐉",
}

local function hash_string(s)
  local h = 5381
  for i = 1, #s do
    h = ((h * 33) + s:byte(i)) % 2147483647
  end
  return h
end

local M = {}

function M.for_key(key)
  return emojis[(hash_string(key) % #emojis) + 1]
end

return M
