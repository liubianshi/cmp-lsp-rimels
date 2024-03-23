local cmp_ok, cmp = pcall(require, "cmp")
if not cmp_ok then
  vim.notify("nvim-cmp not installed", vim.log.levels.ERROR)
  error()
end

-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()
local status_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if status_ok then
  capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

local cmp_keymaps  = require "rime.cmp_keymaps"
local utils        = require "rime.utils"
local default_opts = require "rime.default_opts"
local lspconfig    = require "lspconfig"
local configs      = require "lspconfig.configs"

local M = {}

function M.setup(opts)
  opts = vim.tbl_extend("force", default_opts, opts or {})

  local rime_on_attach = function(client, _)
    utils.create_command_toggle_rime(client)
    utils.create_command_rime_sync()
    utils.create_autocmd_toggle_rime_according_buffer_status(client)
    utils.create_inoremap_start_rime(client, opts.keys.start)
    utils.create_inoremap_stop_rime(client, opts.keys.stop)
  end

  if not configs.rime_ls then
    configs.rime_ls = {
      default_config = {
        name = "rime_ls",
        cmd = opts.cmd,
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
      user_data_dir = opts.rime_user_dir,
      log_dir = opts.rime_user_dir .. "/log",
      max_candidates = opts.max_candidates,
      trigger_characters = opts.trigger_characters,
      schema_trigger_character = opts.schema_trigger_character,
    },
    on_attach = rime_on_attach,
    capabilities = capabilities,
  }

  -- Configure how various keys respond
  cmp.setup { mapping = cmp.mapping.preset.insert(cmp_keymaps) }

  vim.keymap.set({ "i" }, opts.keys.start, function()
    vim.cmd "stopinsert"
    local bufnr = vim.api.nvim_get_current_buf()
    local client = utils.buf_get_rime_ls_client(bufnr)

    if not client then
      utils.buf_attach_rime_ls(bufnr)
      client = utils.buf_get_rime_ls_client(bufnr)
    end

    if not utils.global_rime_enabled() then
      utils.toggle_rime(client)
    end

    if not utils.buf_rime_enabled() then
      utils.buf_toggle_rime(bufnr, true)
    end
    vim.fn.feedkeys("a", "n")
  end, { silent = true, noremap = true, desc = "Toggle Input Method" })

  lspconfig.rime_ls.launch()
end

return M
