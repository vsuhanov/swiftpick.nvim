---@module "swiftpick.storage"

local config = require("swiftpick.config")

---@class SwiftpickEntry
---@field path string
---@field line integer
---@field label string

---@return string
local function EMPTY()
  return config.values.empty_entry_identifier
end

local GLOBAL_CWD_EQUIVALENT = "swiftpick://global"

---@param list (SwiftpickEntry|string)[]
local function trim_trailing_empty(list)
  while #list > 0 and list[#list] == EMPTY() do
    table.remove(list)
  end
end

---@return table<string, (SwiftpickEntry|string)[]>
local function read_data()
  local file = io.open(config.values.storage_file_path, "r")
  if not file then
    return {}
  end
  local content = file:read("*a")
  file:close()
  if not content or content == "" then
    return {}
  end
  local ok, decoded = pcall(vim.fn.json_decode, content)
  return (ok and type(decoded) == "table") and decoded or {}
end

---@param data table<string, (SwiftpickEntry|string)[]>
local function write_data(data)
  local file = io.open(config.values.storage_file_path, "w")
  if not file then
    error("Could not write to storage file at " .. config.values.storage_file_path)
  end
  file:write(vim.fn.json_encode(data) .. "\n")
  file:close()
end

local function create_new_storage_file()
  vim.fn.mkdir(vim.fn.fnamemodify(config.values.storage_file_path, ":h"), "p")
  local file = io.open(config.values.storage_file_path, "w")
  if not file then
    error("Could not create storage file at " .. config.values.storage_file_path)
  end
  file:write("{}\n")
  file:close()
end

---@param a SwiftpickEntry|string
---@param b SwiftpickEntry|string
---@return boolean
local function entries_match(a, b)
  if type(a) == "string" or type(b) == "string" then
    return a == b
  end
  return a.path == b.path and a.line == b.line
end

---@class SwiftpickStorageModule
local M = {}

function M.ensure_storage_exists()
  if vim.fn.filewritable(config.values.storage_file_path) == 0 then
    create_new_storage_file()
    return
  end
  local data = read_data()
  if vim.tbl_isempty(data) then
    write_data({})
  end
end

---@param cwd string
---@return (SwiftpickEntry|string)[]
function M.get_entries_for_cwd(cwd)
  local data = read_data()
  return data[cwd] or {}
end

---@return (SwiftpickEntry|string)[]
function M.get_entries_global()
  return M.get_entries_for_cwd(GLOBAL_CWD_EQUIVALENT)
end

function M.get_entry_at_for_cwd(cwd, index)
  local list = M.get_entries_for_cwd(cwd)
  return list[index]
end

function M.get_entry_at_global(index)
  return M.get_entry_at_for_cwd(GLOBAL_CWD_EQUIVALENT, index)
end

---@param cwd string?
---@param entry SwiftpickEntry
function M.add_entry_for_cwd(cwd, entry)
  if cwd == nil or cwd == "" then
    vim.notify("Cannot add entry to storage: cwd is nil or empty", vim.log.levels.ERROR)
    return
  end

  local data = read_data()
  data[cwd] = data[cwd] or {}

  for _, existing in ipairs(data[cwd]) do
    if entries_match(existing, entry) then
      return
    end
  end

  table.insert(data[cwd], entry)
  write_data(data)
end

---@param entry SwiftpickEntry
function M.add_entry_global(entry)
  M.add_entry_for_cwd(GLOBAL_CWD_EQUIVALENT, entry)
end

---@param cwd string?
---@param entry SwiftpickEntry
function M.remove_entry_for_cwd(cwd, entry)
  if cwd == nil or cwd == "" then
    vim.notify("Cannot remove entry from storage: cwd is nil or empty", vim.log.levels.ERROR)
    return
  end

  local data = read_data()
  if not data[cwd] then
    return
  end

  local filtered = {}
  for _, existing in ipairs(data[cwd]) do
    if not entries_match(existing, entry) then
      table.insert(filtered, existing)
    end
  end

  data[cwd] = filtered
  write_data(data)
end

---@param entry SwiftpickEntry
function M.remove_entry_global(entry)
  M.remove_entry_for_cwd(GLOBAL_CWD_EQUIVALENT, entry)
end

---@param cwd string?
function M.prune_entries(cwd)
  if cwd == nil or cwd == "" then
    vim.notify("Cannot prune entries: cwd is nil or empty", vim.log.levels.ERROR)
    return
  end

  local data = read_data()
  if not data[cwd] then
    return
  end
  local pruned = {}
  local seen = {}
  for _, entry in ipairs(data[cwd]) do
    if type(entry) == "table" then
      local key = entry.path .. ":" .. entry.line
      if not seen[key] then
        seen[key] = true
        table.insert(pruned, entry)
      end
    end
  end
  data[cwd] = pruned
  write_data(data)
end

function M.prune_entries_global()
  M.prune_entries(GLOBAL_CWD_EQUIVALENT)
end

---@param cwd string?
---@param entries (SwiftpickEntry|string)[]
function M.set_entries_for_cwd(cwd, entries)
  if cwd == nil or cwd == "" then
    vim.notify("Cannot set entries: cwd is nil or empty", vim.log.levels.ERROR)
    return
  end

  local data = read_data()
  data[cwd] = entries
  write_data(data)
end

---@param entries (SwiftpickEntry|string)[]
function M.set_entries_global(entries)
  M.set_entries_for_cwd(GLOBAL_CWD_EQUIVALENT, entries)
end

---@param cwd string?
---@param index integer
function M.remove_entry_at_for_cwd(cwd, index)
  if cwd == nil or cwd == "" then
    vim.notify("Cannot remove entry: cwd is nil or empty", vim.log.levels.ERROR)
    return
  end

  local data = read_data()
  if not data[cwd] or not data[cwd][index] then
    return
  end
  table.remove(data[cwd], index)
  write_data(data)
end

---@param index integer
function M.remove_entry_at_global(index)
  M.remove_entry_at_for_cwd(GLOBAL_CWD_EQUIVALENT, index)
end

---@param cwd string?
---@param entry SwiftpickEntry
---@param index integer
function M.add_entry_at_for_cwd(cwd, entry, index)
  if cwd == nil or cwd == "" then
    vim.notify("Cannot add entry: cwd is nil or empty", vim.log.levels.ERROR)
    return
  end

  local data = read_data()
  data[cwd] = data[cwd] or {}
  local list = data[cwd]

  local existing_index = nil
  for i, existing in ipairs(list) do
    if entries_match(existing, entry) then
      existing_index = i
      break
    end
  end

  if existing_index then
    list[existing_index] = EMPTY()

    if #list < index then
      for i = #list + 1, index - 1 do
        list[i] = EMPTY()
      end
      list[index] = entry
    elseif list[index] == EMPTY() then
      list[index] = entry
    else
      table.insert(list, index, entry)
    end

    trim_trailing_empty(list)
    write_data(data)
    return
  end

  if #list < index then
    for i = #list + 1, index - 1 do
      list[i] = EMPTY()
    end
    list[index] = entry
  elseif list[index] == EMPTY() then
    list[index] = entry
  else
    table.insert(list, index, entry)
  end

  write_data(data)
end

---@param entry SwiftpickEntry
---@param index integer
function M.add_entry_at_global(entry, index)
  M.add_entry_at_for_cwd(GLOBAL_CWD_EQUIVALENT, entry, index)
end

function M.flush_local()
  local cwd = vim.fn.getcwd()
  M.set_entries_for_cwd(cwd, {})
end

function M.flush_global()
  M.set_entries_global({})
end

function M.flush_all()
  write_data({})
end

return M
