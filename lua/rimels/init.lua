--- Rimels plugin main module
--- Provides setup and configuration for the rime input method integration
local utils = require "rimels.utils"
local has_setup = false
local M = {}

--- Setup the rimels plugin with provided options
--- @param opts table|nil Configuration options for the plugin
--- @return table The module table for method chaining
function M.setup(opts)
  -- Prevent multiple setup calls
  if has_setup then
    return M
  end
  has_setup = true

  -- Merge user options with defaults
  opts = require("rimels.config").update_option(opts or {})

  -- Initialize rime language server
  utils.rime_ls_setup(opts)

  -- Setup input method toggle keymap
  vim.keymap.set({ "i" }, opts.keys.start, utils.start_rime_ls, {
    silent = true,
    noremap = true,
    desc = "Toggle Input Method",
  })

  -- Initialize and configure completion keymaps
  M.keymaps = require("rimels.cmp_keymaps")
    :setup({
      probes = opts.probes.using,
      detectors = opts.detectors,
    })
    :launch(opts.cmp_keymaps.disable)

  -- Store configuration for later access
  M.opts = opts

  return M
end

--- Public API Functions ---

--- Get the rime_ls LSP client if available
--- @return table|nil The rime_ls client or nil if not found
function M.get_rime_ls_client()
  local clients = vim.lsp.get_clients { name = "rime_ls" }
  return clients[1] -- Return first client or nil if none found
end

return M
