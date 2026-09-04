---Helper functions for rendering swiftpick entries.
---@module "swiftpick.helper.display"

local config = require("swiftpick.config")
local paths = require("swiftpick.helper.paths")
local emoji = require("swiftpick.helper.emoji")

---@return string
local function EMPTY()
  return config.values.empty_entry_identifier
end

---@class SwiftpickDisplayHelper
local M = {}

---Count how many times each path occurs in the entry list.
---@param entries (SwiftpickEntry|string)[]
---@return table<string, integer>
function M.path_counts(entries)
  local counts = {}
  for _, entry in ipairs(entries) do
    if type(entry) == "table" then
      counts[entry.path] = (counts[entry.path] or 0) + 1
    end
  end
  return counts
end

---Emoji prefix for an entry. Entries sharing a path get an extra per-location emoji.
---@param entry SwiftpickEntry
---@param path_counts table<string, integer>
---@return string
function M.prefix(entry, path_counts)
  local file_emoji = emoji.for_key(entry.path or "")
  if path_counts[entry.path] and path_counts[entry.path] > 1 then
    return file_emoji .. emoji.for_key((entry.path or "") .. ":" .. (entry.line or 0))
  end
  return file_emoji
end

---The path of an entry as it should be displayed.
---@param entry SwiftpickEntry|string
---@param cwd string?
---@param display_absolute boolean?
---@return string
function M.path(entry, cwd, display_absolute)
  if type(entry) == "string" then
    if entry == EMPTY() or display_absolute then
      return entry
    end
    return paths.to_relative(entry, cwd --[[@as string]])
  end

  local p = paths.resolve(entry, cwd --[[@as string]]) or ""
  if not display_absolute and cwd then
    p = paths.to_relative(p, cwd)
  end
  return p
end

---The `path:line` location of an entry as it should be displayed.
---@param entry SwiftpickEntry|string
---@param cwd string?
---@param display_absolute boolean?
---@return string
function M.location(entry, cwd, display_absolute)
  local p = M.path(entry, cwd, display_absolute)
  if type(entry) == "string" then
    return p
  end
  return ("%s:%d"):format(p, entry.line or 0)
end

---The full display line for an entry, as shown in the picker list.
---@param entry SwiftpickEntry|string
---@param cwd string?
---@param display_absolute boolean?
---@param path_counts table<string, integer>
---@return string
function M.line(entry, cwd, display_absolute, path_counts)
  if type(entry) == "string" then
    return M.path(entry, cwd, display_absolute)
  end
  return ("%s %s  %s"):format(
    M.prefix(entry, path_counts),
    M.location(entry, cwd, display_absolute),
    entry.label or ""
  )
end

return M
