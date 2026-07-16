---@module "swiftpick.actions"
---@class SwiftpickActions

local state = require("swiftpick.state")
local storage = require("swiftpick.storage")
local paths = require("swiftpick.helper.paths")
local config = require("swiftpick.config")

local function EMPTY()
  return config.values.empty_entry_identifier
end

---@class SwiftpickActions
local M = {}

local function prompt_for_label(default_text, callback)
  local ok, NuiInput = pcall(require, "nui.input")
  if ok then
    local popup_options = {
      position = "50%",
      size = { width = 60 },
      border = {
        style = "rounded",
        text = { top = " label ", top_align = "center" },
      },
      zindex = 200,
    }
    local input = NuiInput(popup_options, {
      prompt = "> ",
      default_value = default_text,
      on_submit = function(value)
        callback(value or default_text)
      end,
    })

    input:mount()
    vim.cmd("startinsert!")
  else
    vim.ui.input({ prompt = "Label: ", default = default_text }, function(value)
      if value then
        callback(value)
      end
    end)
  end
end

---@class SwiftpickAddOpts
---@field filename? string
---@field cwd? string
---@field index? integer
---@field use_global_context? boolean
---@field line? integer
---@field label? string

function M.add(opts)
  opts = opts or {}
  if opts.use_global_context == nil then
    opts.use_global_context = state.use_global_context
  end

  if not opts.filename and not state.opened_picker_from.buf then
    vim.notify(
      "Not adding as no filename was provided, and can't retrieve it from the picker state (probably not open).",
      vim.log.levels.ERROR
    )
    return
  end

  local source_buf = state.opened_picker_from.buf or vim.api.nvim_get_current_buf()
  local source_win = state.opened_picker_from.win or vim.api.nvim_get_current_win()

  local filepath = opts.filename or vim.api.nvim_buf_get_name(source_buf)
  local cwd = opts.cwd or vim.uv.cwd()

  local line = opts.line
  if not line and source_win and vim.api.nvim_win_is_valid(source_win) then
    line = vim.api.nvim_win_get_cursor(source_win)[1]
  end
  line = line or 1

  local function do_add(label)
    local abs_path = paths.to_absolute(filepath, cwd)
    local entry = {
      path = abs_path,
      rel_path = paths.to_relative(abs_path, cwd),
      line = line,
      label = label or "",
    }
    if opts.index then
      if opts.use_global_context then
        storage.add_entry_at_global(entry, opts.index)
      else
        storage.add_entry_at_for_cwd(cwd, entry, opts.index)
      end
    else
      if opts.use_global_context then
        storage.add_entry_global(entry)
      else
        storage.add_entry_for_cwd(cwd, entry)
      end
    end
    require("swiftpick.window").refresh_picker_window()
  end

  if opts.label then
    do_add(opts.label)
    return
  end

  local default_label = ""
  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    local lines = vim.api.nvim_buf_get_lines(source_buf, line - 1, line, false)
    if lines and lines[1] then
      default_label = vim.trim(lines[1])
    end
  end

  prompt_for_label(default_label, function(label)
    do_add(label)
  end)
end

---@class SwiftpickRemoveOpts
---@field file? SwiftpickEntry|integer
---@field cwd? string
---@field use_global_context? boolean

function M.remove(opts)
  opts = opts or {}
  if opts.use_global_context == nil then
    opts.use_global_context = state.use_global_context
  end

  if not opts.file and not state.opened_picker_from.buf then
    vim.notify(
      "Not removing as no file was provided, and can't retrieve it from the picker state (probably not open).",
      vim.log.levels.ERROR
    )
    return
  end

  local cwd = opts.cwd or vim.uv.cwd()

  if not opts.file then
    local buf_path = vim.api.nvim_buf_get_name(state.opened_picker_from.buf)
    local entries = opts.use_global_context and storage.get_entries_global()
      or storage.get_entries_for_cwd(cwd)
    for i, entry in ipairs(entries) do
      if type(entry) == "table" and (entry.path == buf_path or paths.resolve(entry, cwd) == buf_path) then
        if opts.use_global_context then
          storage.remove_entry_at_global(i)
        else
          storage.remove_entry_at_for_cwd(cwd, i)
        end
        require("swiftpick.window").refresh_picker_window()
        return
      end
    end
    return
  end

  local file = opts.file

  if type(file) == "number" then
    local index = file
    if opts.use_global_context then
      storage.remove_entry_at_global(index)
    else
      storage.remove_entry_at_for_cwd(cwd, index)
    end
  elseif type(file) == "table" then
    if opts.use_global_context then
      storage.remove_entry_global(file)
    else
      storage.remove_entry_for_cwd(cwd, file)
    end
  else
    vim.notify(
      "Invalid file identifier for removal: must be entry table or 1-based index number",
      vim.log.levels.ERROR
    )
    return
  end

  require("swiftpick.window").refresh_picker_window()
end

function M.open_picker(opts)
  if state.picker_win ~= nil then
    return
  end
  state.opened_picker_from = { buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win() }
  require("swiftpick.window").create_picker_window(opts)
end

function M.close_picker()
  if state.picker_win and vim.api.nvim_win_is_valid(state.picker_win) then
    vim.api.nvim_win_close(state.picker_win, true)
  end
end

---@class SwiftpickPruneOpts
---@field cwd? string
---@field use_global_context? boolean

function M.prune_entries(opts)
  opts = opts or {}
  if opts.use_global_context == nil then
    opts.use_global_context = state.use_global_context
  end
  local cwd = opts.cwd or vim.uv.cwd()
  if opts.use_global_context then
    storage.prune_entries_global()
  else
    storage.prune_entries(cwd)
  end

  require("swiftpick.window").refresh_picker_window()
end

function M.toggle_display_absolute_paths()
  state.display_absolute_paths = not state.display_absolute_paths
  require("swiftpick.window").refresh_picker_window()
end

function M.set_display_absolute_paths(absolute)
  state.display_absolute_paths = absolute
  require("swiftpick.window").refresh_picker_window()
end

function M.toggle_use_global_context()
  state.use_global_context = not state.use_global_context
  require("swiftpick.window").refresh_picker_window()
end

function M.set_use_global_context(use_global)
  state.use_global_context = use_global
  require("swiftpick.window").refresh_picker_window()
end

function M.switch_to_pick_mode()
  require("swiftpick.window").switch_to_pick_mode()
end

function M.switch_to_edit_mode()
  require("swiftpick.window").switch_to_edit_mode()
end

---@class SwiftpickPickFileOpts
---@field cwd? string
---@field use_global_context? boolean

function M.pick_file(file, opts)
  opts = opts or {}

  local cwd = opts.cwd or vim.uv.cwd()
  local use_global_context = opts.use_global_context
  if use_global_context == nil then
    use_global_context = state.use_global_context
  end

  local entry = file
  if type(file) == "number" then
    entry = use_global_context and storage.get_entry_at_global(file) or storage.get_entry_at_for_cwd(cwd, file)
  end

  if not entry then
    vim.notify("No file specified to pick. Provide a file identifier in the options.", vim.log.levels.ERROR)
    return
  end

  if type(entry) == "string" then
    if entry ~= "" and entry ~= EMPTY() then
      local absolute_path = paths.to_absolute(entry, vim.uv.cwd())
      M.close_picker()
      if state.opened_picker_from.win and vim.api.nvim_win_is_valid(state.opened_picker_from.win) then
        vim.api.nvim_set_current_win(state.opened_picker_from.win)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(absolute_path))
    end
    return
  end

  if type(entry) == "table" then
    if entry.path and entry.path ~= "" then
      local absolute_path = paths.resolve(entry, vim.uv.cwd())
      M.close_picker()
      if state.opened_picker_from.win and vim.api.nvim_win_is_valid(state.opened_picker_from.win) then
        vim.api.nvim_set_current_win(state.opened_picker_from.win)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(absolute_path))
      if entry.line and entry.line > 0 then
        vim.schedule(function()
          local line_count = vim.api.nvim_buf_line_count(0)
          local target_line = math.min(entry.line, line_count)
          vim.api.nvim_win_set_cursor(0, { target_line, 0 })
        end)
      end
    end
  end
end

return M
