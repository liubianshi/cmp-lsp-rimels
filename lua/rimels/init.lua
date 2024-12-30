local cmp_ok, cmp = pcall(require, "cmp")
local blink_ok, blink = pcall(require, "blink.cmp")
if not cmp_ok and not blink_ok then
  vim.notify("nvim-cmp and blink.cmp are not installed", vim.log.levels.ERROR)
  error()
end

-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()
if blink_ok then
  capabilities = blink.get_lsp_capabilities()
else
  local status_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
  if status_ok then
    capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
  end
end

-- Fix: Offset-Encoding issue since Neovim v0.10.2 #38
-- https://github.com/wlh320/rime-ls/issues/38#issuecomment-2559780016
if vim.fn.has "nvim-0.10.2" == 1 and vim.fn.has "nvim-0.11.0" == 0 then
  if capabilities.general then
    capabilities.general.positionEncodings = { "utf-8" }
  else
    capabilities.general = {
      positionEncodings = { "utf-8" },
    }
  end
end

local utils = require "rimels.utils"
local default_opts = require "rimels.default_opts"
local probes = require "rimels.probes"
local detectors = require "rimels.english_environment_detectors"
local cmp_keymaps = require "rimels.cmp_keymaps"
local defined_keymaps = {}

local update_option = function(default, user)
  if not (user and next(user)) then
    return default
  end

  local updated_default = {}
  for key, value in pairs(default) do
    if user[key] then
      if key == "cmd" and type(user[key]) == "string" then
        updated_default[key] = { user[key] }
      elseif key == "cmd" and type(user[key]) == "function" then
        updated_default[key] = user[key]
      elseif type(user[key]) ~= type(value) then
        error(key .. " must be " .. type(value))
      elseif type(value) == "table" then
        updated_default[key] = vim.tbl_extend("force", value, user[key])
      else
        updated_default[key] = user[key]
      end
    else
      updated_default[key] = value -- 如果 user 表格中没有对应 key，则保持默认值不变
    end
  end

  if blink_ok then
    updated_default.long_filter_text = true
    updated_default.cmp_keymaps.disable.numbers = true
    updated_default.cmp_keymaps.disable.punctuation_upload_directly = true
  end

  return updated_default
end

local function start_rime_ls(iters)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = utils.buf_get_rime_ls_client(bufnr)
  vim.cmd "stopinsert"

  if not client then
    utils.buf_attach_rime_ls(bufnr)
    -- Solve the problem that the input method cannot take effect immediately
    -- when starting for the first time
    iters = iters or 0
    if iters <= 100 then
      vim.schedule(function()
        start_rime_ls(iters + 1)
      end)
    end
    return
  end

  if not utils.global_rime_enabled() then
    utils.toggle_rime(client)
  end

  if not utils.buf_rime_enabled() then
    utils.buf_toggle_rime(bufnr, true)
  end

  if blink_ok then
    local show_emitter = require('blink.cmp.completion.list').show_emitter
    if not vim.tbl_contains(show_emitter.listeners, function(cb) return cb == utils.blink_showup_callback end)
    then
      show_emitter:on(utils.blink_showup_callback)
    end
  end

  vim.fn.feedkeys("a", "n")
end

local M = {}

function M.setup(opts)
  local lspconfig = require "lspconfig"
  local configs = require "lspconfig.configs"
  if M.get_rime_ls_client() then
    return M.opts
  end
  opts = update_option(default_opts, opts or {})

  for name, probe in pairs(probes) do
    if vim.fn.index(opts.probes.ignore, name) < 0 then
      opts.probes.using[name] = probe
    end
  end

  opts.probes.using =
    vim.tbl_extend("force", opts.probes.using, opts.probes.add)

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
    capabilities = capabilities,
  }

  -- Configure how various keys respond
  local keymaps = cmp_keymaps:setup({
    probes = opts.probes.using,
    detectors = opts.detectors,
  }).keymaps
  keymaps = utils.filter_cmp_keymaps(keymaps, opts.cmp_keymaps.disable)
  if next(keymaps) then
    defined_keymaps = keymaps
    if cmp_ok then
      cmp.setup { mapping = cmp.mapping.preset.insert(keymaps) }
    end
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

function M.get_keymaps()
  return defined_keymaps
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
