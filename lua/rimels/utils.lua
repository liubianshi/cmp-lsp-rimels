local M = {}
local global_rime_status =  "nvim_rime#global_rime_enabled"
local buffer_rime_status =  "buf_rime_enabled"

local feedkey = function(key, mode)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, true, true),
    mode,
    false
  )
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
    vim.cmd "stopinsert"
    if not M.global_rime_enabled() then
      M.toggle_rime(client)
    end
    if not M.buf_rime_enabled() then
      M.buf_toggle_rime(0, true)
    end
    vim.fn.feedkeys("a", "n")
  end, { desc = "Start Chinese Input Method", noremap = true, buffer = true })
end

function M.create_inoremap_stop_rime(client, key)
  vim.keymap.set(
    "i",
    key,
    function()
      vim.cmd "stopinsert"
      if M.global_rime_enabled() then
        M.toggle_rime(client)
      end
      if M.buf_rime_enabled() then
        M.buf_toggle_rime(0, true)
      end
      vim.fn.feedkeys("a", "n")
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
    if vim.fn.exists('b:rimels_last_entry') == 0 then return fallback() end
    if require('cmp').visible() then return fallback() end
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
      feedkey("<BS>", "n")
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

function M.get_content_before_cursor(shift)
  shift = shift or 0
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  if col < shift then
    return nil
  end
  local line_content = vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]
  return line_content:sub(1, col - shift)
end

function M.global_rime_enabled()
  local exist,status = pcall(vim.api.nvim_get_var, global_rime_status)
  return (exist and status)
end

function M.is_typing_english(shift)
  local content_before = M.get_content_before_cursor(shift)
  if not content_before then
    return nil
  end
  return content_before:match "%s[%w%p]+$"
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

return M
