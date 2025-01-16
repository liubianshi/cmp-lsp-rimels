local M = {}
local global_rime_status = "nvim_rime#global_rime_enabled"
local buffer_rime_status = "buf_rime_enabled"

function M.adjust_for_rimels(entry)
  local input_code = M.get_input_code(entry)
  local cmp_result = M.get_cmp_result(entry)
  -- 临时解决 * 和 [ 被错误吃掉的问题，会跟随 rime-ls 的更新调整
  local special_symbol_pattern = "[%[%]{}]"
  local other_symbol_pattern = "[^%[%]{}]"
  if input_code:match(special_symbol_pattern .. "[A-Za-z]") then
    local pattern =
      string.format("^.*(%s)%s+$", special_symbol_pattern, other_symbol_pattern)
    local prefix = input_code:gsub(pattern, "%1")
    if
      prefix:sub(1, 1) == prefix:sub(2, 2)
      and prefix:sub(1, 1):match(special_symbol_pattern)
    then
      prefix = prefix:sub(2)
    end
    return prefix .. cmp_result
  end
end

function M.blink()
  local blink_ok, blink = pcall(require, "blink.cmp")
  if blink_ok then
    return blink
  end
end

function M.blink_showup_callback(event)
  local opts = require("rimels").setup().opts
  local bufnr = vim.api.nvim_get_current_buf()

  if not M.buf_rime_enabled(bufnr) then
    return
  end
  local context_line = vim.tbl_get(event, "context", "line")
  local cursor = vim.tbl_get(event, "context", "cursor")
  if context_line == nil or cursor == nil then
    return
  end
  local last_char = context_line:sub(cursor[2], cursor[2])

  if last_char:match "[1-9]" then
    local rime_id = M.get_rime_entry_ids(event.items, { only = true })
    if rime_id then
      M.cmp_select_nth(rime_id)
    end
  end

  if vim.tbl_contains(opts.punctuation_upload_directly, last_char) then
    M.cmp_confirm_punction(event.items)
  end
end

function M.blink_apply_keymap(keys_to_commands)
  -- skip if we've already applied the keymaps
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, "i")) do
    if mapping.desc == "blink.cmp.rimels" then
      return
    end
  end

  -- insert mode: uses both snippet and insert commands
  for key, commands in pairs(keys_to_commands) do
    if #commands == 0 then
      goto continue
    end

    local fallback = require("blink.cmp.keymap.fallback").wrap("i", key)
    vim.api.nvim_buf_set_keymap(0, "i", key, "", {
      callback = function()
        if not require("blink.cmp.config").enabled() then
          return fallback()
        end

        for _, command in ipairs(commands) do
          -- special case for fallback
          if command == "fallback" then
            return fallback()

          -- run user defined functions
          elseif type(command) == "function" then
            if command(require "blink.cmp") then
              return
            end

          -- otherwise, run the built-in command
          elseif require("blink.cmp")[command]() then
            return
          end
        end
      end,
      expr = true,
      silent = true,
      noremap = true,
      replace_keycodes = false,
      desc = "blink.cmp.rimels",
    })

    ::continue::
  end
end

function M.buf_attach_rime_ls(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if M.buf_get_rime_ls_client(bufnr) then
    return
  end

  local rimels_clients = vim.lsp.get_clients { name = "rime_ls" }
  if #rimels_clients > 0 then
    local client = rimels_clients[1]
    vim.lsp.buf_attach_client(bufnr, client.id)
    return
  end

  require("lspconfig").rime_ls.launch()
end

function M.buf_get_rime_ls_client(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer_rimels_clients =
    vim.lsp.get_clients { bufnr = bufnr, name = "rime_ls" }
  if #buffer_rimels_clients > 0 then
    return buffer_rimels_clients[1]
  end
  return nil
end

function M.buf_rime_enabled(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local exist, status =
    pcall(vim.api.nvim_buf_get_var, bufnr, buffer_rime_status)
  return (exist and status)
end

function M.buf_toggle_rime(bufnr, buf_only)
  if M.buf_rime_enabled() ~= M.global_rime_enabled() or buf_only then
    vim.api.nvim_buf_set_var(0, buffer_rime_status, not M.buf_rime_enabled())
    return
  end

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local client = M.buf_get_rime_ls_client(bufnr)
  if not client then
    M.buf_attach_rime_ls(bufnr)
    client = M.buf_get_rime_ls_client(bufnr)
  end
  if not client then
    vim.notify("Failed to get rime_ls client", vim.log.levels.ERROR)
    return
  end

  M.toggle_rime(client)
  M.buf_toggle_rime(bufnr, true)
end

function M.cmp()
  if M.blink() then
    return
  end
  local cmp_ok, cmp = pcall(require, "cmp")
  if not cmp_ok then
    vim.notify("nvim-cmp and blink.cmp are not installed", vim.log.levels.ERROR)
    error()
  end
  return cmp
end

function M.cmp_abort()
  if M.cmp() then
    M.cmp().abort()
  end

  if M.blink() then
    M.blink().hide()
  end
end

function M.cmp_close()
  if M.cmp() then
    M.cmp().close()
  end

  if M.blink() then
    M.blink().hide()
  end
end

function M.cmp_confirm(select)
  select = select or true
  if M.cmp() then
    return M.cmp()
      .confirm { behavior = M.cmp().ConfirmBehavior.Insert, select = select }
  end

  if M.blink() then
    if select then
      return M.blink().select_and_accept()
    else
      return M.blink().accept()
    end
  end
end

function M.cmp_confirm_punction(entries)
  local rime_id = M.get_rime_entry_ids(entries, { only = true })
  if not rime_id then
    return
  end

  -- check character before the punctuation
  local word_before = M.get_chars_before_cursor(2)
  if not word_before or word_before == "" or word_before:match "[%s%w%p]" then
    M.cmp_close()
  else
    M.set_last_entry(entries[rime_id])
    M.cmp_select_nth(rime_id)
  end
end

function M.cmp_without_processing()
  if M.blink() then
    return true
  end
  return nil
end

function M.cmp_select_nth(n)
  local entries = M.get_entries() or {}
  if M.cmp() then
    if not M.is_cmp_visible() then
      return
    end
    if n == 0 then
      return
    end
    for _ = 1, n do
      M.cmp().select_next_item { behavior = M.cmp().SelectBehavior.Select }
    end

    M.set_last_entry(entries[n])
    return M.cmp().confirm { behavior = M.cmp().ConfirmBehavior.Insert }
  end

  if M.blink() then
    vim.api.nvim_buf_set_var(0, "rimels_last_entry", entries[n])
    return M.blink().accept { index = n }
  end
end

function M.create_autocmd_toggle_rime_according_buffer_status(client)
  -- Close rime_ls when opening a new window
  local rime_group =
    vim.api.nvim_create_augroup("RimeAutoToggle", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufRead" }, {
    pattern = "*",
    group = rime_group,
    callback = function(ev)
      local bufnr = ev.buf
      if not M.buf_get_rime_ls_client(bufnr) then
        return
      end
      local buf_rime_enabled = M.buf_rime_enabled(bufnr)
      local global_rime_enabled = M.global_rime_enabled()
      if buf_rime_enabled ~= global_rime_enabled then
        M.toggle_rime(client)
      end
    end,
    desc = "Start or stop rime_ls according current buffer",
  })
end

function M.create_command_rime_sync()
  vim.api.nvim_create_user_command("RimeSync", function()
    vim.lsp.buf.execute_command {
      command = "rime-ls.sync-user-data",
    }
  end, { nargs = 0 })
end

function M.create_command_toggle_rime(client)
  vim.api.nvim_create_user_command("ToggleRime", function(opt)
    local bufnr = vim.api.nvim_get_current_buf()
    local args = opt.args
    if
      (not args or args == "")
      or (args == "on" and not M.global_rime_enabled())
      or (args == "off" and M.global_rime_enabled())
    then
      M.toggle_rime(client)
    elseif args == "start" and not M.global_rime_enabled() then
      M.toggle_rime(client)
    end
    M.buf_toggle_rime(bufnr, true)
  end, { nargs = "?", desc = "Toggle Rime" })
end

function M.create_inoremap_esc(key)
  vim.keymap.set(
    "i",
    key,
    "<cmd>stopinsert<cr>",
    { desc = "Stop insert", noremap = true, buffer = true }
  )
end

function M.create_inoremap_start_rime(client, key)
  vim.keymap.set("i", key, function()
    if not M.global_rime_enabled() then
      M.toggle_rime(client)
    end
    if not M.buf_rime_enabled() then
      M.buf_toggle_rime(0, true)
    end
  end, {
    desc = "Start Chinese Input Method",
    noremap = true,
    buffer = true,
  })
end

function M.create_inoremap_stop_rime(client, key)
  vim.keymap.set("i", key, function()
    if M.is_cmp_visible() then
      M.cmp_abort()
    end
    if M.global_rime_enabled() then
      M.toggle_rime(client)
    end
    if M.buf_rime_enabled() then
      M.buf_toggle_rime(0, true)
    end
  end, {
    desc = "Stop Chinese Input Method",
    noremap = true,
    expr = true,
    buffer = true,
  })
end

function M.create_inoremap_undo(key)
  local fallback = function()
    local keys = vim.api.nvim_replace_termcodes(key, true, false, true)
    vim.api.nvim_feedkeys(keys, "n", false)
  end

  vim.keymap.set("i", key, function()
    if M.blink() then
      return M.blink().cancel()
    end
    if vim.fn.exists "b:rimels_last_entry" == 0 then
      return fallback()
    end
    if M.is_cmp_visible() then
      return fallback()
    end
    local entry = vim.api.nvim_buf_get_var(0, "rimels_last_entry")
    if
      not entry.filterText
      or not entry.textEdit
      or not entry.textEdit.newText
      or vim.fn.line "." ~= entry.textEdit.range["end"].line + 1
    then
      return fallback()
    end
    local text_cmp = entry.textEdit.newText
    local text_input = entry.filterText

    local content_before = M.get_content_before_cursor(0) or ""
    if not content_before:match(text_cmp .. "$") then
      return fallback()
    end
    local char_num = vim.fn.strchars(text_cmp)
    for _ = 1, char_num do
      M.feedkey("<BS>", "n")
    end
    text_input = text_input:gsub(".*_", "")
    vim.schedule(function()
      vim.api.nvim_put({ text_input }, "c", false, true)
    end)
  end, { desc = "rimels: undo last completion", noremap = true, buffer = true })
end

function M.error_rime_ls_not_start_yet()
  local status_ok, notify = pcall(require, "notify")
  if status_ok then
    notify("Start rime-ls with command ToggleRimeLS", "error", {
      title = "rime-ls framework not start yet",
    })
  else
    vim.fn.echoerr "Start rime-ls with command ToggleRimeLS"
  end
end

function M.fallback(fallback, lhs)
  if not fallback then
    return
  end

  if type(fallback) == "function" then
    return fallback()
  end

  if lhs and type(lhs) == "string" then
    if M.cmp() then
      local bufnr = vim.api.nvim_get_current_buf()
      fallback = require("cmp.utils.keymap").fallback(bufnr, "i", lhs)
    elseif M.blink() then
      fallback = require("blink.cmp.keymap.fallback").wrap("i", lhs)
    end
    fallback = fallback or function()
      M.feedkey(lhs, "n")
    end
    return fallback()
  end
end

function M.feedkey(key, mode)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, true, true),
    mode,
    false
  )
end

function M.generate_capabilities()
  -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  if M.blink() then
    capabilities = M.blink().get_lsp_capabilities(capabilities)
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

  return capabilities
end

function M.generate_mapping(fun, opts)
  if M.cmp() then
    return M.cmp().mapping(fun, opts)
  end

  if M.blink() then
    return {
      fun,
      "fallback",
    }
  end
end

function M.filter_cmp_keymaps(keymaps, disable)
  if not keymaps then
    return {}
  end
  if not disable then
    return keymaps
  end

  if disable.space then
    keymaps["<Space>"] = nil
  end
  if disable.enter then
    keymaps["<CR>"] = nil
  end
  if disable.backspace then
    keymaps["<BS>"] = nil
  end
  if disable.brackets then
    keymaps["["] = nil
    keymaps["]"] = nil
  end
  if disable.numbers then
    for numkey = 0, 9 do
      local numkey_str = tostring(numkey)
      keymaps[numkey_str] = nil
    end
  end

  if disable.punctuation_upload_directly then
    local mapped_symbols =
      require("rimels.default_opts").punctuation_upload_directly
    local disabled_symbols = mapped_symbols
    if type(disable.punctuation_upload_directly) == "table" then
      disabled_symbols = vim.tbl_filter(function(symbol)
        return vim.tbl_contains(mapped_symbols, symbol)
      end, disable.punctuation_upload_directly)
    end
    for _, symbol in ipairs(disabled_symbols) do
      keymaps[symbol] = nil
    end
  end

  return keymaps
end

function M.get_chars_after_cursor(length)
  length = length or 1
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line_content = vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]
  return line_content:sub(col + 1, col + length)
end

function M.get_chars_before_cursor(colnums_before, length)
  length = length or 1
  if colnums_before < length then
    return nil
  end
  local content_before = M.get_content_before_cursor(colnums_before - length)
  if not content_before then
    return nil
  end
  return content_before:sub(-length, -1)
end

function M.get_cmp_result(entry)
  if M.cmp() then
    return vim.tbl_get(entry, "completion_item", "textEdit", "newText")
  end

  if M.blink() then
    return vim.tbl_get(entry, "textEdit", "newText")
  end
end

function M.get_cmp_source_name(entry)
  if not entry then
    return
  end
  if M.cmp() then
    return entry.source.name
  end
  if M.blink() then
    return entry.source_id
  end
end

function M.get_content_before_cursor(shift)
  shift = shift or 0
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  if col < shift then
    return nil
  end
  local line_content = vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]
  return line_content:sub(1, col - shift)
end

function M.get_entries()
  if M.cmp() then
    return M.cmp().get_entries()
  end

  if M.blink() then
    return require("blink.cmp.completion.list").items
  end
end

function M.get_first_entry()
  local entries = M.get_entries()
  if entries and #entries > 0 then
    return entries[1]
  end
end

function M.get_input_code(entry)
  if M.cmp() then
    return entry.completion_item.filterText
  end
  if M.blink() then
    return entry.filterText
  end
end

function M.get_mappings()
  if M.cmp() then
    return require("cmp.config").get().mapping
  end

  if M.blink() then
    return {}
    -- return require('blink.cmp.keymap').get_mappings(require('blink.cmp.config').keymap)
  end
end

function M.get_rime_entry_ids(entries, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    first = false,
    only = true,
  })

  local ids = {}
  for id, entry in ipairs(entries) do
    if M.is_rime_entry(entry) then
      table.insert(ids, id)
      if opts.first then
        break
      end
      if opts.only and #ids > 1 then
        return
      end
    end
  end

  if opts.first or opts.only then
    return ids[1]
  end
  return ids
end

function M.get_selected_entry()
  if M.cmp() then
    return M.cmp().get_selected_entry()
  end

  if M.blink() then
    return require("blink.cmp.completion.list").get_selected_item()
  end
end

function M.global_rime_enabled()
  local exist, status = pcall(vim.api.nvim_get_var, global_rime_status)
  return (exist and status)
end

function M.is_eol()
  return (vim.fn.col "." == vim.fn.col "$")
end

function M.is_rime_entry(entry)
  if not entry then
    return false
  end

  if M.cmp() then
    return vim.tbl_get(entry, "source", "name") == "nvim_lsp"
      and vim.tbl_get(entry, "source", "source", "client", "name") == "rime_ls"
      and M.get_input_code(entry) ~= M.get_cmp_result(entry)
  end

  if M.blink() then
    return entry.source_id == "lsp"
      and vim.lsp.get_client_by_id(entry.client_id).name == "rime_ls"
      and M.get_input_code(entry) ~= M.get_cmp_result(entry)
  end
end

function M.is_typing_english(shift)
  local content_before = M.get_content_before_cursor(shift)
  if not content_before then
    return nil
  end
  return content_before:match "%s[%w%p]+$"
end

function M.is_cmp_visible()
  if M.cmp() then
    return M.cmp().visible()
  else
    return M.blink().is_visible()
  end
end

function M.launch_lsp_server(opts)
  local lspconfig = require "lspconfig"
  local lspconfigs = require "lspconfig.configs"

  local rime_on_attach = function(client, _)
    M.create_command_toggle_rime(client)
    M.create_command_rime_sync()
    M.create_autocmd_toggle_rime_according_buffer_status(client)
    M.create_inoremap_start_rime(client, opts.keys.start)
    M.create_inoremap_stop_rime(client, opts.keys.stop)
    M.create_inoremap_esc(opts.keys.esc)
    M.create_inoremap_undo(opts.keys.undo)
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
      enabled = M.global_rime_enabled(),
      shared_data_dir = opts.shared_data_dir,
      user_data_dir = opts.user_data_dir or opts.rime_user_dir,
      log_dir = opts.rime_user_dir .. "/log",
      max_candidates = opts.max_candidates,
      long_filter_text = M.blink() and true or opts.long_filter_text,
      trigger_characters = opts.trigger_characters,
      schema_trigger_character = opts.schema_trigger_character,
      always_incomplete = opts.always_incomplete,
      paging_characters = opts.paging_characters,
    },
    on_attach = rime_on_attach,
    capabilities = M.generate_capabilities(),
  }

  lspconfig.rime_ls.launch()
end

function M.set_last_entry(entry)
  if M.cmp() then
    return vim.api.nvim_buf_set_var(
      0,
      "rimels_last_entry",
      entry.completion_item
    )
  end
  if M.blink() then
    return vim.api.nvim_buf_set_var(0, "rimels_last_entry", entry)
  end
end

function M.start_rime_ls(iters)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = M.buf_get_rime_ls_client(bufnr)
  vim.cmd "stopinsert"

  if not client then
    M.buf_attach_rime_ls(bufnr)
    -- Solve the problem that the input method cannot take effect immediately
    -- when starting for the first time
    iters = iters or 0
    if iters <= 100 then
      vim.schedule(function()
        M.start_rime_ls(iters + 1)
      end)
    end
    return
  end

  if not M.global_rime_enabled() then
    M.toggle_rime(client)
  end

  if not M.buf_rime_enabled() then
    M.buf_toggle_rime(bufnr, true)
  end

  if M.blink() then
    local show_emitter = require("blink.cmp.completion.list").show_emitter
    if
      not vim.tbl_contains(show_emitter.listeners, function(cb)
        return cb == M.blink_showup_callback
      end)
    then
      show_emitter:on(M.blink_showup_callback)
    end
  end

  vim.fn.feedkeys("a", "n")
end

function M.toggle_rime(client)
  client = client or M.buf_get_rime_ls_client()
  if not client or client.name ~= "rime_ls" then
    return
  end
  vim.schedule(function()
    client.request(
      "workspace/executeCommand",
      { command = "rime-ls.toggle-rime" },
      function(_, result, ctx, _)
        if ctx.client_id == client.id then
          vim.api.nvim_set_var(global_rime_status, result)
        end
      end
    )
  end)
end

return M
