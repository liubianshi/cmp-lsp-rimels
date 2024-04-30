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

local utils        = require "rimels.utils"
local default_opts = require "rimels.default_opts"
local lspconfig    = require "lspconfig"
local configs      = require "lspconfig.configs"
local probes       = require "rimels.probes"
local detectors    = require "rimels.english_environment_detectors"
local cmp_keymaps  = require("rimels.cmp_keymaps")

local update_option = function(default, user)
  if not (user and next(user)) then
    return default
  end

  local updated_default = {}
  for key, value in pairs(default) do
    if user[key] then
      if key == "cmd" and type(user[key]) == "string" then
        updated_default[key] = { user[key] }
      elseif type(user[key]) ~= type(value) then
        error(key .. " must be " .. type(value))
      elseif type(value) == "table" then
        updated_default[key] = vim.tbl_extend("force", value, user[key])
      else
        updated_default[key] = user[key]
      end
    else
      updated_default[key] = value  -- 如果 user 表格中没有对应 key，则保持默认值不变
    end
  end

  return updated_default
end

local start_rime_ls = function()
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
end

local M = {}

function M.setup(opts)
  if M.get_rime_ls_client() then return M.opts end
  opts = update_option(default_opts, opts or {})

  for name,probe in pairs(probes) do
    if vim.fn.index(opts.probes.ignore, name) < 0 then
      opts.probes.using[name] = probe
    end
  end
  opts.probes.using = vim.tbl_extend(
    "force",
    opts.probes.using,
    opts.probes.add
  )

  opts.detectors = {
    with_treesitter = vim.tbl_extend(
        "force",
        detectors.with_treesitter,
        opts.detectors.with_treesitter or {}
    ),
    with_syntax = vim.tbl_extend(
      "force",
      detectors.with_syntax,
      opts.detectors.with_syntax or {}
    ),
  }

  local rime_on_attach = function(client, _)
    utils.create_command_toggle_rime(client)
    utils.create_command_rime_sync()
    utils.create_autocmd_toggle_rime_according_buffer_status(client)
    utils.create_inoremap_start_rime(client, opts.keys.start)
    utils.create_inoremap_stop_rime(client, opts.keys.stop)
    utils.create_inoremap_esc(opts.keys.esc)
    utils.create_inoremap_undo(opts.keys.undo)
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
      always_incomplete = opts.always_incomplete,
      max_candidates = opts.max_candidates,
    },
    on_attach = rime_on_attach,
    capabilities = capabilities,
  }

  -- Configure how various keys respond
  local keymaps = cmp_keymaps:set_probes_detects(
    opts.probes.using,
    opts.detectors
  ).keymaps
  keymaps = utils.filter_cmp_keymaps(keymaps, opts.cmp_keymaps.disable)
  if next(keymaps) then
    cmp.setup { mapping = cmp.mapping.preset.insert(keymaps) }
  end

  vim.keymap.set({ "i" }, opts.keys.start, start_rime_ls, {
    silent = true,
    noremap = true,
    desc = "Toggle Input Method",
  })

  lspconfig.rime_ls.launch()

  M.opts = opts
  return M.opts
end

function M.get_rime_ls_client()
  local active_clients = vim.lsp.get_active_clients()
  if #active_clients == 0 then return nil end

  for _, client in ipairs(active_clients) do
    if client.name == "rime_ls" then
      return client
    end
  end

  return nil
end

return M
