---@module "swiftpick.window"

---@class SwiftpickOpenPickerOverrides
---@field display_absolute_paths? boolean
---@field use_global_context? boolean

local config = require("swiftpick.config")
local binds = require("swiftpick.binds")
local storage = require("swiftpick.storage")
local paths = require("swiftpick.helper.paths")
local emoji = require("swiftpick.helper.emoji")
local state = require("swiftpick.state")
local footer = require("swiftpick.helper.footer")

local HINT_NAMESPACE = vim.api.nvim_create_namespace("swiftpick_hints")
local NUMBERWIDTH = 2
local edit_line_count = 0
local exit_edit_mode_auto_cmd_id = nil
local show_hints_in_edit_mode_autocmd_id = nil

---@return string
local function EMPTY()
  return config.values.empty_entry_identifier
end

---@param entries (SwiftpickEntry|string)[]
---@return string[]
local function get_display_entries(entries)
  local cwd = vim.uv.cwd()
  local display = {}

  local path_count = {}
  for _, entry in ipairs(entries) do
    if type(entry) == "table" then
      path_count[entry.path] = (path_count[entry.path] or 0) + 1
    end
  end

  for _, entry in ipairs(entries) do
    if type(entry) == "string" then
      if entry == EMPTY() then
        table.insert(display, entry)
      elseif state.display_absolute_paths then
        table.insert(display, entry)
      else
        table.insert(display, paths.to_relative(entry, cwd))
      end
    elseif type(entry) == "table" then
      local p = entry.path or ""
      if not state.display_absolute_paths and cwd then
        p = paths.to_relative(p, cwd)
      end
      local label = entry.label or ""
      local file_emoji = emoji.for_key(entry.path or "")
      local prefix
      if path_count[entry.path] and path_count[entry.path] > 1 then
        local location_emoji = emoji.for_key((entry.path or "") .. ":" .. (entry.line or 0))
        prefix = file_emoji .. location_emoji
      else
        prefix = file_emoji
      end
      table.insert(display, ("%s %s:%d  %s"):format(prefix, p, entry.line or 0, label))
    end
  end

  return display
end

---@param buf_size { width: integer, height: integer }
---@param footer_content string
---@return { width: integer, height: integer }
local function get_window_size(buf_size, footer_content)
  local footer_size = #footer_content
  local padding_r = 2
  local numberwidth_extra_padding = 2

  return {
    width = vim.fn.max({
      vim.fn.min({
        buf_size.width + NUMBERWIDTH + numberwidth_extra_padding,
        vim.o.columns - 4,
      }),
      footer_size,
    }) + padding_r,

    height = vim.fn.min({
      vim.fn.max({ buf_size.height + 1, 5 }),
      vim.o.lines - 4,
    }),
  }
end

---@param entry_buf_nr integer
---@return { width: integer, height: integer }
local function get_buf_size(entry_buf_nr)
  local line_count = vim.api.nvim_buf_line_count(entry_buf_nr)

  local max_line_length = 0
  for i = 1, line_count do
    local line_length = #vim.api.nvim_buf_get_lines(entry_buf_nr, i - 1, i, false)[1]
    if line_length > max_line_length then
      max_line_length = line_length
    end
  end

  return {
    width = max_line_length,
    height = line_count,
  }
end

---@param picker_buf_handle integer
---@param display_entries string[]
---@return vim.api.keyset.win_config
local function get_centered_win_config(picker_buf_handle, display_entries)
  local footer_content = footer.get_picker_footer(display_entries)
  local win_size = get_window_size(get_buf_size(picker_buf_handle), footer_content)

  local row = math.floor((vim.o.lines - win_size.height) / 2)
  local col = math.floor((vim.o.columns - win_size.width) / 2)

  return {
    relative = "editor",
    row = row,
    col = col,
    width = win_size.width,
    height = win_size.height,
    border = "rounded",
    style = "minimal",
    title = state.use_global_context and "swiftpick [global]" or "swiftpick",
    title_pos = "center",
    footer = footer_content,
    footer_pos = "center",
  }
end

local function show_hints()
  local char_keybinds = config.values.keybinds.pick_entry.chars

  local hints = {}
  for i = 1, 10 do
    local key = char_keybinds["_" .. i]
    if key ~= nil then
      hints[i] = key
    end
  end

  local buf = state.edit_mode and state.picker_list_edit_buf or state.picker_list_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    error("Cannot show hints: picker buffer " .. buf .. " is not valid")
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, HINT_NAMESPACE, 0, -1)

  local count = vim.api.nvim_buf_line_count(buf)
  for i, label in ipairs(hints) do
    if i <= count then
      vim.api.nvim_buf_set_extmark(buf, HINT_NAMESPACE, i - 1, 0, {
        sign_text = label,
        sign_hl_group = "Comment",
      })
    end
  end
end

---@param overrides_applied SwiftpickOpenPickerOverrides
local function on_exit_picker(overrides_applied)
  vim.api.nvim_buf_delete(state.picker_list_buf, { force = true })
  vim.api.nvim_buf_delete(state.picker_list_edit_buf, { force = true })

  state.picker_list_buf = nil
  state.picker_win = nil

  state.opened_picker_from = { buf = nil, win = nil }

  if overrides_applied.display_absolute_paths then
    state.display_absolute_paths = state.session_memory.before_overrides.display_absolute_paths
    state.session_memory.before_overrides.display_absolute_paths = nil
  end

  if overrides_applied.use_global_context then
    state.use_global_context = state.session_memory.before_overrides.use_global_context
    state.session_memory.before_overrides.display_absolute_paths = nil
  end

  if exit_edit_mode_auto_cmd_id then
    vim.api.nvim_del_autocmd(exit_edit_mode_auto_cmd_id)
    exit_edit_mode_auto_cmd_id = nil
  end
  if show_hints_in_edit_mode_autocmd_id then
    vim.api.nvim_del_autocmd(show_hints_in_edit_mode_autocmd_id)
    show_hints_in_edit_mode_autocmd_id = nil
  end
end

---@param override_opts? SwiftpickOpenPickerOverrides
---@return SwiftpickOpenPickerOverrides
local function apply_open_picker_overrides(override_opts)
  local display_absolute_paths_overridden = false
  local use_global_context_overridden = false

  override_opts = override_opts or {}

  if override_opts.display_absolute_paths ~= nil then
    state.session_memory.before_overrides.display_absolute_paths = state.display_absolute_paths
    state.display_absolute_paths = not override_opts.display_absolute_paths
    display_absolute_paths_overridden = true
  end

  if override_opts.use_global_context ~= nil then
    state.session_memory.before_overrides.use_global_context = state.use_global_context
    state.use_global_context = override_opts.use_global_context
    use_global_context_overridden = true
  end

  if
    not display_absolute_paths_overridden and not state.session_memory.default_value_for_display_absolute_paths_set
  then
    state.display_absolute_paths = config.values.display_absolute_path_by_default
    state.session_memory.default_value_for_display_absolute_paths_set = true
  end

  if not use_global_context_overridden and not state.session_memory.default_value_for_use_global_context_set then
    state.use_global_context = config.values.use_global_context_by_default
    state.session_memory.default_value_for_use_global_context_set = true
  end

  return {
    display_absolute_paths = display_absolute_paths_overridden,
    use_global_context = use_global_context_overridden,
  }
end

---@class SwiftpickWindow
local M = {}

function M.create_picker_window(open_picker_overrides)
  local overrides_applied = apply_open_picker_overrides(open_picker_overrides)

  state.picker_list_buf = vim.api.nvim_create_buf(false, true)
  state.picker_win = vim.api.nvim_open_win(
    state.picker_list_buf,
    true,
    { relative = "editor", width = 1, height = 1, row = 0, col = 0, style = "minimal" }
  )

  state.picker_list_edit_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(state.picker_list_edit_buf, "swiftpick://edit")
  vim.bo[state.picker_list_edit_buf].buftype = "acwrite"

  local function make_win_leave_autocmd(buf)
    vim.api.nvim_create_autocmd("WinLeave", {
      once = true,
      callback = function()
        on_exit_picker(overrides_applied)
      end,
      buf = buf,
    })
  end
  make_win_leave_autocmd(state.picker_list_buf)
  make_win_leave_autocmd(state.picker_list_edit_buf)

  binds.create_picker_keybinds(state.picker_list_buf)
  binds.create_edit_mode_keybinds(state.picker_list_edit_buf)
  M.switch_to_edit_mode()
end

function M.switch_to_pick_mode()
  if not state.picker_win or not vim.api.nvim_win_is_valid(state.picker_win) then
    vim.notify("Cannot switch to pick mode: picker window is not valid", vim.log.levels.ERROR)
    return
  end

  state.edit_mode = false
  vim.cmd("stopinsert")
  vim.api.nvim_win_set_buf(state.picker_win, state.picker_list_buf)

  vim.wo[state.picker_win].number = true
  vim.wo[state.picker_win].cursorline = true
  vim.wo[state.picker_win].numberwidth = NUMBERWIDTH

  M.refresh_picker_window()
end

function M.switch_to_edit_mode()
  if not state.picker_win or not vim.api.nvim_win_is_valid(state.picker_win) then
    vim.notify("Cannot switch to edit mode: picker window is not valid", vim.log.levels.ERROR)
    return
  end

  state.edit_mode = true
  vim.bo[state.picker_list_edit_buf].modified = false
  vim.api.nvim_win_set_buf(state.picker_win, state.picker_list_edit_buf)

  vim.wo[state.picker_win].number = true
  vim.wo[state.picker_win].cursorline = true
  vim.wo[state.picker_win].numberwidth = NUMBERWIDTH

  exit_edit_mode_auto_cmd_id = vim.api.nvim_create_autocmd("BufWriteCmd", {
    once = false,
    buf = state.picker_list_edit_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(state.picker_list_edit_buf, 0, -1, false)
      local cwd = vim.uv.cwd()
      local seen = {}
      local valid_entries = {}

      for _, line in ipairs(lines) do
        if line == EMPTY() then
          table.insert(valid_entries, line)
        else
          local content = line:match("^.-%s([/%.%w].*)$") or line
          local path_str, line_num, label = content:match("^(.+):(%d+)%s+(.*)$")
          if path_str and line_num then
            local abs = paths.to_absolute(path_str, cwd)
            local key = abs .. ":" .. line_num
            if vim.fn.filereadable(abs) == 1 and not seen[key] then
              seen[key] = true
              table.insert(valid_entries, { path = abs, line = tonumber(line_num), label = label or "" })
            end
          end
        end
      end

      while #valid_entries > 0 and valid_entries[#valid_entries] == EMPTY() do
        table.remove(valid_entries)
      end

      if state.use_global_context then
        storage.set_entries_global(valid_entries)
      else
        storage.set_entries_for_cwd(cwd, valid_entries)
      end

      vim.bo[state.picker_list_edit_buf].modified = false

      vim.schedule(function()
        M.switch_to_pick_mode()
      end)
    end,
  })

  edit_line_count = vim.api.nvim_buf_line_count(state.picker_list_edit_buf)
  show_hints_in_edit_mode_autocmd_id = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    once = false,
    buf = state.picker_list_edit_buf,
    callback = function()
      local current_count = vim.api.nvim_buf_line_count(state.picker_list_edit_buf)
      if current_count ~= edit_line_count then
        edit_line_count = current_count
        show_hints()
      end
    end,
  })

  M.refresh_picker_window()
end

function M.refresh_picker_window()
  local buf = state.edit_mode and state.picker_list_edit_buf or state.picker_list_buf
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local raw_entries = state.use_global_context and storage.get_entries_global()
      or storage.get_entries_for_cwd(vim.uv.cwd() --[[@as string]])

    local display_entries = get_display_entries(raw_entries)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_entries)

    if buf == state.picker_list_edit_buf then
      vim.bo[buf].modified = false
    end

    vim.api.nvim_win_set_config(state.picker_win, get_centered_win_config(buf, display_entries))

    show_hints()
    return
  end
end

return M
