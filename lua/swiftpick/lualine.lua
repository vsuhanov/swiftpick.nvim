local state = require("swiftpick.state")
local storage = require("swiftpick.storage")
local config = require("swiftpick.config")

local M = {}

---@param files (SwiftpickEntry|string)[]
---@param opts SwiftpickLualineComponentOpts
local function get_shortcuts_string(files, opts)
  local keys = {}

  local current_file = vim.api.nvim_buf_get_name(0)

  for i, file in ipairs(files) do
    local table_key = "_" .. i
    if type(file) == "string" and file == config.values.empty_entry_identifier then
      if opts.empty_entry ~= nil and opts.empty_entry ~= "" then
        table.insert(keys, opts.empty_entry)
      end
    else
      local is_active = type(file) == "table" and file.path == current_file
      local key = (not opts.use_digits and config.values.keybinds.pick_entry.chars[table_key])
        or config.values.keybinds.pick_entry.digits[table_key]
      table.insert(keys, is_active and ("%s%s%s"):format(opts.active_prefix, key, opts.active_suffix) or key)
    end
  end

  return table.concat(keys, opts.concat_separator)
end

---@type SwiftpickLualineComponentOpts
local defaults = {
  prefix = "󱗆  ",
  local_indicator = "󰟙",
  local_indicator_active = "!",
  local_prefix = " ",
  local_suffix = "",
  local_global_separator = "   ",
  global_indicator = "",
  global_indicator_active = "!",
  global_prefix = " ",
  global_suffix = "",
  active_prefix = "[",
  active_suffix = "]",
  empty_entry = "",
  concat_separator = " ",
  use_digits = false,
  only_show_active_context = false,
}

---@class SwiftpickLualineComponentOpts
---@field prefix string|nil
---@field local_indicator string|nil
---@field local_indicator_active string|nil
---@field local_prefix string|nil
---@field local_suffix string|nil
---@field local_global_separator string|nil
---@field global_indicator string|nil
---@field global_indicator_active string|nil
---@field global_prefix string|nil
---@field global_suffix string|nil
---@field active_prefix string|nil
---@field active_suffix string|nil
---@field empty_entry string|nil
---@field concat_separator string|nil
---@field use_digits boolean|nil
---@field only_show_active_context boolean|nil

function M.component(opts)
  local values = vim.tbl_deep_extend("force", defaults, opts or {})

  return function()
    local files_local = storage.get_entries_for_cwd(vim.uv.cwd() --[[@as string]])
    local files_global = storage.get_entries_global()

    local shortcuts_local_string = get_shortcuts_string(files_local, values)
    local shortcuts_global_string = get_shortcuts_string(files_global, values)

    if values.only_show_active_context then
      if state.use_global_context then
        return ("%s%s%s%s%s"):format(
          values.prefix,
          values.global_indicator_active,
          values.global_prefix,
          shortcuts_global_string,
          values.global_suffix
        )
      else
        return ("%s%s%s%s%s"):format(
          values.prefix,
          values.local_indicator_active,
          values.local_prefix,
          shortcuts_local_string,
          values.local_suffix
        )
      end
    end

    return ("%s%s%s%s%s%s%s%s%s"):format(
      values.prefix,
      state.use_global_context and values.local_indicator or values.local_indicator_active,
      values.local_prefix,
      shortcuts_local_string,
      values.local_suffix,
      values.local_global_separator,
      state.use_global_context and values.global_indicator_active or values.global_indicator,
      values.global_prefix,
      shortcuts_global_string,
      values.global_suffix
    )
  end
end

return M
