local utils = require "rimels.utils"
local config = require "rimels.config"
local cmp_keymaps = require "rimels.cmp_keymaps"

local has_setup = false
local M = {}

function M.setup(opts)
  if has_setup then
    return M
  end
  has_setup = true
  local lspconfig = require "lspconfig"
  local lspconfigs = require "lspconfig.configs"
  opts = config.update_option(opts or {})

  local rime_on_attach = function(client, _)
    utils.create_command_toggle_rime(client)
    utils.create_command_rime_sync()
    utils.create_autocmd_toggle_rime_according_buffer_status(client)
    utils.create_inoremap_start_rime(client, opts.keys.start)
    utils.create_inoremap_stop_rime(client, opts.keys.stop)
    utils.create_inoremap_esc(opts.keys.esc)
    utils.create_inoremap_undo(opts.keys.undo)
  end

  if not lspconfigs.rime_ls then
    lspconfigs.rime_ls = {
      default_config = {
        name = "rime_ls",
        cmd = opts.cmd,
        root_dir = function() end,
        filetypes = opts.filetypes,
        single_file_support = opts.single_file_support,
      },
      settings = opts.settings,
      docs = {
        description = opts.docs.description,
      },
    }
  end

  lspconfig.rime_ls.setup {
    init_options = {
      enabled = utils.global_rime_enabled(),
      shared_data_dir = opts.shared_data_dir,
      user_data_dir = opts.user_data_dir or opts.rime_user_dir,
      log_dir = opts.rime_user_dir .. "/log",
      max_candidates = opts.max_candidates,
      long_filter_text = opts.long_filter_text,
      trigger_characters = opts.trigger_characters,
      schema_trigger_character = opts.schema_trigger_character,
      always_incomplete = opts.always_incomplete,
      paging_characters = opts.paging_characters,
    },
    on_attach = rime_on_attach,
    capabilities = utils.generate_capabilities(),
  }

  M.keymaps = M.set_keymaps(opts)
  vim.keymap.set({ "i" }, opts.keys.start, utils.start_rime_ls, {
    silent = true,
    noremap = true,
    desc = "Toggle Input Method",
  })

  lspconfig.rime_ls.launch()

  M.opts = opts

  return M
end

function M.set_keymaps(opts)
  opts = opts or M.opts or config.update_option {}
  -- Configure how various keys respond
  local keymaps = cmp_keymaps:setup {
    probes = opts.probes.using,
    detectors = opts.detectors,
  }
  return keymaps:launch(opts.cmp_keymaps.disable)
end

function M.get_rime_ls_client()
  local client = vim.lsp.get_clients { name = "rime_ls" }
  if #client == 0 then
    return nil
  else
    return client
  end
end

return M
