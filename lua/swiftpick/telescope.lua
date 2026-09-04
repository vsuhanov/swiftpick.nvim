---Telescope picker for swiftpick entries, with a preview of the saved location.
---@module "swiftpick.telescope"

local config = require("swiftpick.config")
local state = require("swiftpick.state")
local storage = require("swiftpick.storage")
local paths = require("swiftpick.helper.paths")
local display_helper = require("swiftpick.helper.display")

---@class SwiftpickTelescope
local M = {}

---@type table Options passed through `telescope.setup({ extensions = { swiftpick = {...} } })`.
M.ext_config = {}

---@return string
local function EMPTY()
  return config.values.empty_entry_identifier
end

---@return SwiftpickTelescopeOpts
local function telescope_config()
  local values = config.values.telescope
  if values == nil then
    return config.defaults.telescope
  end
  return values
end

---@return table?
local function require_telescope()
  local ok = pcall(require, "telescope")
  if not ok then
    vim.notify(
      "swiftpick: the telescope picker requires nvim-telescope/telescope.nvim to be installed",
      vim.log.levels.ERROR
    )
    return nil
  end

  return {
    pickers = require("telescope.pickers"),
    finders = require("telescope.finders"),
    conf = require("telescope.config").values,
    actions = require("telescope.actions"),
    action_state = require("telescope.actions.state"),
    entry_display = require("telescope.pickers.entry_display"),
  }
end

---@class SwiftpickTelescopeContext
---@field cwd string
---@field use_global_context boolean
---@field display_absolute_paths boolean

---@class SwiftpickTelescopeItem
---@field index integer Position of the entry in the stored list.
---@field entry SwiftpickEntry|string
---@field prefix string
---@field location string
---@field label string
---@field filename string?
---@field lnum integer

---Collect the stored entries as items ready for display, skipping empty slots.
---@param ctx SwiftpickTelescopeContext
---@return SwiftpickTelescopeItem[]
local function collect_items(ctx)
  local raw_entries = ctx.use_global_context and storage.get_entries_global()
    or storage.get_entries_for_cwd(ctx.cwd)

  local path_counts = display_helper.path_counts(raw_entries)
  local items = {}

  for index, entry in ipairs(raw_entries) do
    if type(entry) == "table" then
      table.insert(items, {
        index = index,
        entry = entry,
        prefix = display_helper.prefix(entry, path_counts),
        location = display_helper.location(entry, ctx.cwd, ctx.display_absolute_paths),
        label = entry.label or "",
        filename = paths.resolve(entry, ctx.cwd),
        lnum = entry.line or 1,
      })
    elseif type(entry) == "string" and entry ~= EMPTY() and entry ~= "" then
      table.insert(items, {
        index = index,
        entry = entry,
        prefix = "",
        location = display_helper.path(entry, ctx.cwd, ctx.display_absolute_paths),
        label = "",
        filename = paths.to_absolute(entry, ctx.cwd),
        lnum = 1,
      })
    end
  end

  return items
end

---@param items SwiftpickTelescopeItem[]
---@param telescope table
---@return function
local function make_entry_maker(items, telescope)
  local index_width = 1
  local prefix_width = 0
  local location_width = 1

  for _, item in ipairs(items) do
    index_width = math.max(index_width, #tostring(item.index))
    prefix_width = math.max(prefix_width, vim.fn.strdisplaywidth(item.prefix))
    location_width = math.max(location_width, vim.fn.strdisplaywidth(item.location))
  end

  local columns = {
    { width = index_width, right_justify = true },
  }
  if prefix_width > 0 then
    table.insert(columns, { width = prefix_width })
  end
  table.insert(columns, { width = location_width })
  table.insert(columns, { remaining = true })

  local displayer = telescope.entry_display.create({
    separator = " ",
    items = columns,
  })

  return function(item)
    local function make_display()
      local values = { { tostring(item.index), "TelescopeResultsNumber" } }
      if prefix_width > 0 then
        table.insert(values, item.prefix)
      end
      table.insert(values, { item.location, "TelescopeResultsIdentifier" })
      table.insert(values, { item.label, "TelescopeResultsComment" })
      return displayer(values)
    end

    return {
      value = item.entry,
      swiftpick_index = item.index,
      ordinal = item.location .. " " .. item.label,
      display = make_display,
      filename = item.filename,
      lnum = item.lnum,
      col = 1,
    }
  end
end

---@param ctx SwiftpickTelescopeContext
---@param telescope table
---@return table
local function make_finder(ctx, telescope)
  local items = collect_items(ctx)
  return telescope.finders.new_table({
    results = items,
    entry_maker = make_entry_maker(items, telescope),
  })
end

---@param ctx SwiftpickTelescopeContext
---@return string
local function make_title(ctx)
  local title = ctx.use_global_context and "swiftpick [global]" or "swiftpick"
  if ctx.display_absolute_paths then
    return title .. " [abs]"
  end
  return title
end

---@param picker table
---@param ctx SwiftpickTelescopeContext
---@param telescope table
local function refresh(picker, ctx, telescope)
  pcall(function()
    picker.prompt_border:change_title(make_title(ctx))
  end)
  picker:refresh(make_finder(ctx, telescope), { reset_prompt = false })
end

---Open a telescope picker listing the swiftpick entries with a preview of each location.
---@param opts? table Telescope options, plus `cwd`, `use_global_context` and `display_absolute_paths`.
function M.picker(opts)
  local telescope = require_telescope()
  if not telescope then
    return
  end

  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.ext_config or {}), opts or {})

  ---@type SwiftpickTelescopeContext
  local ctx = {
    cwd = opts.cwd or vim.uv.cwd(),
    use_global_context = opts.use_global_context,
    display_absolute_paths = opts.display_absolute_paths,
  }
  if ctx.use_global_context == nil then
    ctx.use_global_context = state.use_global_context or false
  end
  if ctx.display_absolute_paths == nil then
    ctx.display_absolute_paths = state.display_absolute_paths or false
  end

  local mappings = vim.tbl_deep_extend(
    "force",
    vim.deepcopy(telescope_config().mappings or {}),
    opts.mappings or {}
  )

  telescope.pickers
    .new(opts, {
      prompt_title = make_title(ctx),
      preview_title = opts.preview_title or "location",
      finder = make_finder(ctx, telescope),
      sorter = telescope.conf.generic_sorter(opts),
      previewer = telescope.conf.grep_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        telescope.actions.select_default:replace(function()
          local entry = telescope.action_state.get_selected_entry()
          telescope.actions.close(prompt_bufnr)
          if not entry then
            return
          end
          require("swiftpick.actions").pick_file(entry.value, {
            cwd = ctx.cwd,
            use_global_context = ctx.use_global_context,
          })
        end)

        local function delete_entry()
          local entry = telescope.action_state.get_selected_entry()
          if not entry or not entry.swiftpick_index then
            return
          end
          if ctx.use_global_context then
            storage.remove_entry_at_global(entry.swiftpick_index)
          else
            storage.remove_entry_at_for_cwd(ctx.cwd, entry.swiftpick_index)
          end
          refresh(telescope.action_state.get_current_picker(prompt_bufnr), ctx, telescope)
        end

        local function toggle_use_global_context()
          ctx.use_global_context = not ctx.use_global_context
          refresh(telescope.action_state.get_current_picker(prompt_bufnr), ctx, telescope)
        end

        local function toggle_display_absolute_paths()
          ctx.display_absolute_paths = not ctx.display_absolute_paths
          refresh(telescope.action_state.get_current_picker(prompt_bufnr), ctx, telescope)
        end

        local handlers = {
          delete_entry = delete_entry,
          toggle_use_global_context = toggle_use_global_context,
          toggle_display_absolute_paths = toggle_display_absolute_paths,
        }

        for name, handler in pairs(handlers) do
          local keys = mappings[name]
          if keys then
            for mode, key in pairs(keys) do
              if key then
                map(mode, key, handler, { desc = "swiftpick: " .. name:gsub("_", " ") })
              end
            end
          end
        end

        return true
      end,
    })
    :find()
end

return M
