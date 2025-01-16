local utils = require "rimels.utils"
local has_setup = false
local M = {}

function M.setup(opts)
  if has_setup then
    return M
  end
  has_setup = true

  opts = require("rimels.config").update_option(opts or {})

  utils.launch_lsp_server(opts)

  vim.keymap.set({ "i" }, opts.keys.start, utils.start_rime_ls, {
    silent = true,
    noremap = true,
    desc = "Toggle Input Method",
  })

  M.keymaps = require("rimels.cmp_keymaps")
    :setup({
      probes = opts.probes.using,
      detectors = opts.detectors,
    })
    :launch(opts.cmp_keymaps.disable)

  M.opts = opts

  return M
end

-- public api

function M.get_rime_ls_client()
  local client = vim.lsp.get_clients { name = "rime_ls" }
  if #client == 0 then
    return nil
  else
    return client
  end
end

return M
