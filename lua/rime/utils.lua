local probes = require('rime.probes')
local M = {}

function M.get_content_before_cursor(shift)
  shift = shift or 0
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  if col < shift then
    return nil
  end
  local line_content = vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]
  return line_content:sub(1, col - shift)
end

function M.get_chars_before_cursor(colnums_before, length)
  length = length or 1
  if colnums_before < length then
    return nil
  end
  local content_before = M.get_line_before(colnums_before - length)
  if not content_before then
    return nil
  end
  return content_before:sub(-length, -1)
end

function M.is_typing_english(shift)
  local content_before = M.get_content_before_cursor(shift)
  if not content_before then
    return nil
  end
  return content_before:match "%s[%w%p]+$"
end

function M.in_english_environment()
  local info = vim.inspect_pos()
  local englist_env = false
  for _, ts in ipairs(info.treesitter) do
    if ts.capture == "markup.math" or ts.capture == "markup.raw" then
      return true
    elseif ts.capture == "markup.raw.block" then
      englist_env = true
    elseif ts.capture == "comment" then
      return false
    end
  end
  if englist_env then
    return englist_env
  end

  for _, syn in ipairs(info.syntax) do
    if
      syn.hl_group_link:match "MathBlock"
      or syn.hl_group_link:match "NoFormatted"
    then
      return true
    end
  end
  return englist_env
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

function M.rime_enabled()
  return vim.g.rime_enabled == true
end

function M.buf_rime_enabled()
  return vim.b.buf_rime_enabled == true
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
        vim.g.rime_enabled = result
      end
    end
  )
end

function M.buf_get_rime_ls_client(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local current_buffer_clients = vim.lsp.buf_get_clients(bufnr)
  if #current_buffer_clients > 0 then
    for _, client in ipairs(current_buffer_clients) do
      if client.name == "rime_ls" then
        return client
      end
    end
  end
  return nil
end

function M.buf_attach_rime_ls(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if M.buf_get_rime_ls_client(bufnr) then
    return
  end

  -- Get all currently active LSP clients
  local active_clients = vim.lsp.get_active_clients()
  if #active_clients > 0 then
    for _, client in ipairs(active_clients) do
      if client.name == "rime_ls" then
        vim.lsp.buf_attach_client(bufnr, client.id)
        return
      end
    end
  end

  require("lspconfig").rime_ls.launch()
end

function M.buf_toggle_rime(bufnr, adjust_globl_status)
  adjust_globl_status = adjust_globl_status or true

  if M.buf_rime_enabled ~= M.rime_enabled() or not adjust_globl_status then
    vim.b.buf_rime_enabled = not M.buf_rime_enabled()
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
  M.buf_toggle_rime(bufnr, false)
end

function M.create_command_toggle_rime(client)
  vim.api.nvim_create_user_command("ToggleRime", function(opt)
    local args = opt.args
    if
      not args
      or (args == "on" and not M.rime_enabled())
      or (args == "off" and M.rime_enabled())
    then
      M.toggle_rime(client)
    elseif args == "start" and not M.rime_enabled() then
      M.toggle_rime(client)
    end
  end, { nargs = "?", desc = "Toggle Rime" })
end

function M.create_command_rime_sync()
  vim.api.nvim_create_user_command("RimeSync", function()
    vim.lsp.buf.execute_command {
      command = "rime-ls.sync-user-data",
    }
  end, { nargs = 0 })
end

function M.create_autocmd_toggle_rime_according_buffer_status(client)
  -- Close rime_ls when opening a new window
  local rime_group =
    vim.api.nvim_create_augroup("RimeAutoToggle", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    pattern = "*",
    group = rime_group,
    callback = function()
      if
        (M.rime_enabled() and not M.buf_rime_enabled())
        or (not M.rime_enabled and M.buf_rime_enabled())
      then
        M.toggle_rime(client)
      end
    end,
    desc = "Start or stop rime_ls according current buffer",
  })
end

function M.create_inoremap_start_rime(client, key)
  vim.keymap.set("i", key, function()
    vim.cmd "stopinsert"
    if not vim.g.rime_enabled then
      M.toggle_rime(client)
    end
    if not M.buf_rime_enabled then
      M.buf_toggle_rime_ls_status()
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
      if vim.g.rime_enabled then
        M.toggle_rime(client)
      end
      if M.buf_rime_enabled then
        M.buf_toggle_rime_ls_status()
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

function M.probes_all_passed(probes_ignored)
  if probes_ignored and probes_ignored == "all" then
    return true
  end
  for name, probe in pairs(probes) do
    if vim.fn.index(probes_ignored, name) < 0 and probe() then
      return false
    end
  end
  return true
end
return M
