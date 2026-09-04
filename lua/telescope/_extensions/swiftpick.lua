---Telescope extension registration for swiftpick.
---@module "telescope._extensions.swiftpick"

local ok, telescope = pcall(require, "telescope")
if not ok then
  error("swiftpick.nvim telescope extension requires nvim-telescope/telescope.nvim")
end

return telescope.register_extension({
  setup = function(ext_config)
    require("swiftpick.telescope").ext_config = ext_config or {}
  end,
  exports = {
    swiftpick = function(opts)
      require("swiftpick.telescope").picker(opts)
    end,
    ["local"] = function(opts)
      opts = vim.tbl_deep_extend("force", opts or {}, { use_global_context = false })
      require("swiftpick.telescope").picker(opts)
    end,
    global = function(opts)
      opts = vim.tbl_deep_extend("force", opts or {}, { use_global_context = true })
      require("swiftpick.telescope").picker(opts)
    end,
  },
})
