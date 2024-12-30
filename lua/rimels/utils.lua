local M = {}
local global_rime_status =  "nvim_rime#global_rime_enabled"
local buffer_rime_status =  "buf_rime_enabled"

local default_ops = require('rimels.default_opts')
local cmp_ok, cmp = pcall(require, "cmp")
local blink_ok, blink = pcall(require, "blink.cmp")
if not cmp_ok and not blink_ok then
  vim.notify("nvim-cmp and blink.cmp are not installed", vim.log.levels.ERROR)
  error()
end

function M.blink_showup_callback(event)
  local bufnr = vim.api.nvim_get_current_buf()
  if not M.buf_rime_enabled(bufnr) then return end
  local context_line = vim.tbl_get(event, "context", "line")
  if context_line == nil then return end
  local last_char = context_line:sub(-1, -1)

  if last_char:match("[1-9]") then
    local rime_id = M.get_rime_entry_ids(event.items, {only = true})
    if rime_id then
      M.cmp_select_nth(rime_id)
    end
  end

  if vim.tbl_contains(
    default_ops.punctuation_upload_directly,
    last_char
  ) then
    M.cmp_confirm_punction(event.items)
  end
end

function M.buf_attach_rime_ls(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if M.buf_get_rime_ls_client(bufnr) then
    return
  end

  local rimels_clients = vim.lsp.get_clients({name = "rime_ls"})
  if #rimels_clients > 0 then
    local client = rimels_clients[1]
    vim.lsp.buf_attach_client(bufnr, client.id)
    return
  end

  require("lspconfig").rime_ls.launch()
end

function M.buf_get_rime_ls_client(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer_rimels_clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rime_ls'})
  if #buffer_rimels_clients > 0 then
    return buffer_rimels_clients[1]
  end
  return nil
end

function M.buf_rime_enabled(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local exist,status = pcall(vim.api.nvim_buf_get_var, bufnr, buffer_rime_status)
  return (exist and status)
end

function M.cmp_abort()
  if cmp_ok then
    cmp.abort()
  end

  if blink_ok then
    blink.hide()
  end
end

function M.cmp_close()
  if cmp_ok then
    cmp.close()
  end

  if blink_ok then
    blink.hide()
  end
end

function M.cmp_confirm(select)
  select = select or true
  if cmp_ok then
    return cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = select}
  end

  if blink_ok then
    if select then
      return blink.select_and_accept()
    else
      return blink.accept()
    end
  end
end

function M.cmp_confirm_punction(entries)
  if entries and #entries == 1 then
    -- check character before the punctuation
    local word_before = M.get_chars_before_cursor(2)
    if not word_before or word_before == "" or word_before:match "[%s%w%p]" then
      M.cmp_close()
    else
      M.set_last_entry(entries[1])
      M.cmp_confirm(true)
    end
  end
end

function M.cmp_without_processing()
  if blink_ok then return true end
  return nil
end

function M.cmp_select_nth(n)
  local entries = M.get_entries() or {}
  if cmp_ok then
    if not M.is_cmp_visible() then return end
    if n == 0 then return end
    for _ = 1, n do
      cmp.select_next_item { behavior = cmp.SelectBehavior.Select }
    end

    M.set_last_entry(entries[n])
    return cmp.confirm { behavior = cmp.ConfirmBehavior.Insert }
  end

  if blink_ok then
    vim.api.nvim_buf_set_var(0, 'rimels_last_entry', entries[n])
    return blink.accept({ index = n })
  end
end

function M.buf_toggle_rime(bufnr, buf_only)
  if M.buf_rime_enabled() ~= M.global_rime_enabled() or buf_only
  then
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

function M.create_autocmd_toggle_rime_according_buffer_status(client)
  -- Close rime_ls when opening a new window
  local rime_group =
    vim.api.nvim_create_augroup("RimeAutoToggle", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufRead"}, {
    pattern = "*",
    group = rime_group,
    callback = function(ev)
      local bufnr = ev.buf
      if not M.buf_get_rime_ls_client(bufnr) then
        return
      end
      local buf_rime_enabled = M.buf_rime_enabled(bufnr)
      local global_rime_enabled = M.global_rime_enabled()
      if (buf_rime_enabled ~= global_rime_enabled) then
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
  vim.keymap.set('i', key, "<cmd>stopinsert<cr>",
      {desc = "Stop insert", noremap = true, buffer = true})
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
  vim.keymap.set(
    "i",
    key,
    function()
      if M.is_cmp_visible() then
        M.cmp_abort()
      end
      if M.global_rime_enabled() then
        M.toggle_rime(client)
      end
      if M.buf_rime_enabled() then
        M.buf_toggle_rime(0, true)
      end
    end,
    {
      desc = "Stop Chinese Input Method",
      noremap = true,
      expr = true,
      buffer = true,
    }
  )
end

function M.create_inoremap_undo(key)
  local fallback = function()
    local keys = vim.api.nvim_replace_termcodes(key, true, false, true)
    vim.api.nvim_feedkeys(keys, 'n', false)
  end

  vim.keymap.set("i", key, function()
    if blink_ok then
      return blink.cancel()
    end
    if vim.fn.exists('b:rimels_last_entry') == 0 then return fallback() end
    if M.is_cmp_visible() then return fallback() end
    local entry = vim.api.nvim_buf_get_var(0, 'rimels_last_entry')
    if
      not entry.filterText or not entry.textEdit or not entry.textEdit.newText
      or vim.fn.line('.') ~= entry.textEdit.range['end'].line + 1
    then
      return fallback()
    end
    local text_cmp = entry.textEdit.newText
    local text_input = entry.filterText

    local content_before = M.get_content_before_cursor(0) or ""
    if not content_before:match(text_cmp .. '$') then return fallback() end
    local char_num = vim.fn.strchars(text_cmp)
    for _ = 1, char_num do
      M.feedkey("<BS>", "n")
    end
    text_input = text_input:gsub(".*_", "")
    vim.schedule(function() vim.api.nvim_put({text_input}, "c", false, true) end)
  end, {desc = "rimels: undo last completion", noremap = true, buffer = true})
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
  if not fallback then return end

  if type(fallback) == "function" then
    return fallback()
  end

  if lhs and type(lhs) == "string" then
    if cmp_ok then
      local bufnr = vim.api.nvim_get_current_buf()
      fallback = require('cmp.utils.keymap').fallback(bufnr, "i", lhs)
    elseif blink_ok then
      fallback = require('blink.cmp.keymap.fallback').wrap('i', lhs)
    end
    fallback = fallback or function() M.feedkey(lhs, "n") end
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

function M.generate_mapping(fun, opts)
  if cmp_ok then
    return cmp.mapping(fun, opts)
  end

  if blink_ok then
    return {
      fun,
      "fallback"
    }
  end
end

function M.filter_cmp_keymaps(keymaps, disable)
  if not keymaps then return {} end
  if not disable then return keymaps end

  if disable.space then keymaps['<Space>'] = nil end
  if disable.enter then keymaps['<CR>'] = nil end
  if disable.backspace then keymaps['<BS>'] = nil end
  if disable.brackets then
    keymaps['['] = nil
    keymaps[']'] = nil
  end
  if disable.numbers then
    for numkey = 0, 9 do
      local numkey_str = tostring(numkey)
      keymaps[numkey_str] = nil
    end
  end

  if disable.punctuation_upload_directly then
    local mapped_symbols = require('rimels.default_opts').punctuation_upload_directly
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
  if cmp_ok then
    return vim.tbl_get(entry, "completion_item", "textEdit", "newText")
  end

  if blink_ok then
    return vim.tbl_get(entry, "textEdit", "newText")
  end
end

function M.get_cmp_source_name(entry)
  if not entry then return end
  if cmp_ok then
    return entry.source.name
  end
  if blink_ok then
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
  if cmp_ok then
    return cmp.get_entries()
  end

  if blink_ok then
    return require('blink.cmp.completion.list').items
  end
end

function M.get_first_entry()
  local entries = M.get_entries()
  if entries and #entries > 0 then
    return entries[1]
  end
end

function M.get_input_code(entry)
  if cmp_ok then
    return entry.completion_item.filterText
  end
  if blink_ok then
    return entry.filterText
  end
end

function M.get_mappings()
  if cmp_ok then
    return require('cmp.config').get().mapping
  end

  if blink_ok then
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
  if cmp_ok then
    return cmp.get_selected_entry()
  end

  if blink_ok then
    return require('blink.cmp.completion.list').get_selected_item()
  end
end

function M.global_rime_enabled()
  local exist,status = pcall(vim.api.nvim_get_var, global_rime_status)
  return (exist and status)
end

function M.is_eol()
  return (vim.fn.col('.') == vim.fn.col('$'))
end

function M.is_rime_entry(entry)
  if not entry then return false end

  if cmp_ok then
    return vim.tbl_get(entry, "source", "name") == "nvim_lsp"
      and vim.tbl_get(entry, "source", "source", "client", "name") == "rime_ls"
      and M.get_input_code(entry) ~= M.get_cmp_result(entry)
  end

  if blink_ok then
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
  if cmp_ok then
    return cmp.visible()
  else
    return blink.is_visible()
  end
end

function M.set_last_entry(entry)
  if cmp_ok then
    return vim.api.nvim_buf_set_var(0, 'rimels_last_entry', entry.completion_item)
  end
  if blink_ok then
    return vim.api.nvim_buf_set_var(0, 'rimels_last_entry', entry)
  end
end


function M.toggle_rime(client)
  client = client or M.buf_get_rime_ls_client()
  if not client or client.name ~= "rime_ls" then
    return
  end
  client.request(
    "workspace/executeCommand",
    { command = "rime-ls.toggle-rime" },
    function(_, result, ctx, _)
      if ctx.client_id == client.id then
        vim.api.nvim_set_var(global_rime_status, result)
      end
    end
  )
end

function M.transform_result(entry, new)
  if not entry then return end
  if cmp_ok then
    entry.completion_item.textEdit.newText = new
  end

  if blink_ok then
    entry.label = new
  end

  return entry
end

return M

