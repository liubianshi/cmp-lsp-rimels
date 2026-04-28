local M = {}

local has_nvim_0_10_2 = vim.fn.has "nvim-0.10.2" == 1
local has_nvim_0_11 = vim.fn.has "nvim-0.11.0" == 1

local global_rime_status = "nvim_rime#global_rime_enabled"
local buffer_rime_status = "buf_rime_enabled"

-- Cached modules and values for performance
local blink_cmp

---@return table
local function get_blink_cmp()
  if blink_cmp == nil then
    blink_cmp = require "blink.cmp"
  end
  return blink_cmp
end

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

--- Apply blink.cmp keymaps to the current buffer
---
--- This function sets up insert mode keymaps for blink.cmp completion commands.
--- It avoids duplicate application by checking existing mappings and handles
--- various command types including fallback, user functions, and built-in commands.
---
--- @param keys_to_commands table A table mapping keys to arrays of commands
function M.blink_apply_keymap(keys_to_commands)
  -- Early return if keymaps already applied to avoid duplicate mappings
  local existing_mappings = vim.api.nvim_buf_get_keymap(0, "i")
  local DESC_PREFIX = "blink.cmp: rimels"
  for _, mapping in ipairs(existing_mappings) do
    if mapping.desc == DESC_PREFIX then
      return
    end
  end

  -- Get blink.cmp instance once and cache it
  local blink = get_blink_cmp()

  -- Cache required modules to reduce repeated require() calls
  local blink_config = require "blink.cmp.config"

  -- Apply keymaps for each key-command combination
  for key, commands in pairs(keys_to_commands) do
    -- Skip keys with no commands to avoid unnecessary mappings
    if #commands > 0 then
      -- Set up the keymap with optimized callback
      vim.api.nvim_buf_set_keymap(0, "i", key, "", {
        callback = function()
          -- Check if blink.cmp is currently enabled
          if not blink_config.enabled() then
            M.fallback(key)
            return
          end

          -- Execute commands in sequence until one succeeds
          for _, command in ipairs(commands) do
            if command == "fallback" then
              M.fallback(key)
              return
            elseif type(command) == "function" then
              if command(blink) then
                return
              end
            elseif blink[command] and blink[command]() then
              return
            end
          end
        end,
        expr = false,
        silent = true,
        noremap = true,
        desc = DESC_PREFIX,
      })
    end
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

  M.launch_rime_ls()
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
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if M.buf_rime_enabled(bufnr) ~= M.global_rime_enabled() or buf_only then
    vim.api.nvim_buf_set_var(
      bufnr,
      buffer_rime_status,
      not M.buf_rime_enabled(bufnr)
    )
    return
  end

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

function M.cmp_close()
  local blink = get_blink_cmp()
  if blink and blink.is_visible() then
    blink.hide()
  end
end

function M.cmp_confirm(select)
  local blink = get_blink_cmp()

  select = select ~= false
  if select then
    return blink.select_and_accept()
  else
    return blink.accept()
  end
end

function M.cmp_confirm_punction(entries)
  local rime_id = M.get_rime_entry_ids(entries, { only = true })
  if not rime_id then
    return
  end

  -- check character before the punctuation
  local word_before = M.get_chars_before_cursor(2)
  if not word_before or word_before == "" then
    M.cmp_close()
  elseif not word_before:match "[%s%w%p]" then
    M.set_last_entry(entries[rime_id])
    M.cmp_select_nth(rime_id)
  end
end

function M.cmp_without_processing()
  return true
end

function M.cmp_select_nth(n, entries)
  local blink = get_blink_cmp()

  entries = entries or blink.get_items() or {}
  vim.b.rimels_last_entry = entries[n]
  blink.accept { index = n }
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
    local client = M.buf_get_rime_ls_client()
    if client and client.exec_cmd then -- Neovim ≥ 0.10
      client:exec_cmd {
        title = "Sync Rime user data",
        command = "rime-ls.sync-user-data",
      }
    elseif client then -- 旧版兼容
      ---@diagnostic disable-next-line: deprecated
      vim.lsp.buf.execute_command {
        command = "rime-ls.sync-user-data",
      }
    end
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
      M.cmp_close()
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
    -- Use vim.b for buffer-local variables for better performance and readability
    if vim.b.rimels_last_entry == nil then
      return fallback()
    end
    if M.is_cmp_visible() then
      return fallback()
    end

    local entry = vim.b.rimels_last_entry
    -- Guard against malformed entry
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

    -- Ensure the text before the cursor ends with the completed text
    if not content_before:match(vim.pesc(text_cmp) .. "$") then
      return fallback()
    end

    -- Undo the completion by deleting characters and re-inserting original input
    local char_num = vim.fn.strchars(text_cmp)
    M.feedkey(string.rep("<BS>", char_num), "n")

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

function M.fallback(lhs)
  if type(lhs) ~= "string" or lhs == "" then
    error("rimels.utils.fallback: lhs must be a non-empty string", 2)
  end

  local function feed(key, mode)
    local translated = key:find("\128") and key or vim.keycode(key)
    vim.api.nvim_feedkeys(translated, mode or "n", false)
  end

  -- blink.cmp V1 returns a key string; V2 returns a `{ key, mode }[]` array.
  local keys = require("blink.cmp.keymap.fallback").wrap("i", lhs)()
  if type(keys) == "string" then
    feed(keys)
  elseif type(keys) == "table" then
    for _, k in ipairs(keys) do feed(k.key, k.mode) end
  end

  return true
end

function M.feedkey(key, mode)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, true, true),
    mode,
    false
  )
end

function M.generate_capabilities()
  local blink = get_blink_cmp()
  if not blink then
    return {}
  end

  -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities = blink.get_lsp_capabilities(capabilities)

  -- Fix: Offset-Encoding issue since Neovim v0.10.2 #38
  if has_nvim_0_10_2 and not has_nvim_0_11 then
    capabilities.general = capabilities.general or {}
    capabilities.general.positionEncodings = { "utf-8" }
  end

  return capabilities
end

-- Defensive: the trailing "fallback" guards against a mapping function
-- returning nil/false. blink_apply_keymap walks the command list in order,
-- so if `fun` ever forgets to `return utils.fallback(lhs)` on a path,
-- "fallback" still consumes the key instead of silently swallowing it.
function M.generate_mapping(fun)
  return {
    fun,
    "fallback",
  }
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

  return keymaps
end

function M.get_chars_after_cursor(length)
  length = length or 1
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line_content = vim.api.nvim_get_current_line()
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
  return vim.tbl_get(entry, "textEdit", "newText")
end

function M.get_cmp_source_name(entry)
  if not entry then
    return
  end
  return entry.source_id
end

function M.get_content_before_cursor(shift)
  shift = shift or 0
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  if col < shift then
    return nil
  end
  local line_content = vim.api.nvim_get_current_line()
  return line_content:sub(1, col - shift)
end

function M.get_first_entry()
  local blink = get_blink_cmp()
  if not blink then
    return
  end
  local entries = blink.get_items()
  if entries and #entries > 0 then
    return entries[1]
  end
end

function M.get_input_code(entry)
  return entry.filterText
end

function M.get_mappings()
  local blink = get_blink_cmp()
  if not blink then
    return {}
  end
  return require("blink.cmp.keymap").get_mappings(
    require("blink.cmp.config").keymap,
    "default"
  )
end

function M.get_rime_entry_ids(entries, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    first = false,
    only = false,
    number = nil,
  })
  if opts.number and type(opts.number) == "string" then
    opts.number = tonumber(opts.number)
  end

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
      if opts.number and #ids == opts.number - 1 then
        return id
      end
    end
  end

  if opts.first or opts.only then
    return ids[1]
  end
  return ids
end

function M.get_selected_entry()
  local blink = get_blink_cmp()
  if not blink then
    return
  end
  return require("blink.cmp.completion.list").get_selected_item()
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

  local input = M.get_input_code(entry)
  local result = M.get_cmp_result(entry)
  local client = vim.lsp.get_client_by_id(entry.client_id)

  return entry.source_id == "lsp"
      and client
      and client.name == "rime_ls"
      and input ~= result
      and input:sub(-result:len(), -1) ~= result
end

function M.is_typing_english(shift)
  local content_before = M.get_content_before_cursor(shift)
  if not content_before then
    return nil
  end
  return content_before:match "%s[%w%p]+$"
end

function M.is_cmp_visible()
  local blink = get_blink_cmp()
  return blink and blink.is_visible()
end

function M.rime_ls_setup(opts)
  local rime_on_attach = function(client, _)
    M.create_command_toggle_rime(client)
    M.create_command_rime_sync()
    M.create_autocmd_toggle_rime_according_buffer_status(client)
    M.create_inoremap_start_rime(client, opts.keys.start)
    M.create_inoremap_stop_rime(client, opts.keys.stop)
    M.create_inoremap_esc(opts.keys.esc)
    M.create_inoremap_undo(opts.keys.undo)
  end

  local lsp_opts = {
    init_options = {
      enabled = M.global_rime_enabled(),
      shared_data_dir = opts.shared_data_dir,
      user_data_dir = opts.user_data_dir or opts.rime_user_dir,
      log_dir = opts.rime_user_dir .. "/log",
      max_candidates = opts.max_candidates,
      long_filter_text = get_blink_cmp() and true or opts.long_filter_text,
      trigger_characters = opts.trigger_characters,
      schema_trigger_character = opts.schema_trigger_character,
      always_incomplete = opts.always_incomplete,
      paging_characters = opts.paging_characters,
    },
    on_attach = rime_on_attach,
    capabilities = M.generate_capabilities(),
  }

  if not has_nvim_0_11 then
    local lspconfigs = require "lspconfig.configs"
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

    require("lspconfig").rime_ls.setup(lsp_opts)
  else
    lsp_opts.name = "rime_ls"
    lsp_opts.cmd = opts.cmd
    vim.lsp.config("rime_ls", lsp_opts)
  end
end

function M.launch_rime_ls()
  if has_nvim_0_11 then
    vim.lsp.enable "rime_ls"
  else
    require("lspconfig").rime_ls.launch()
  end
end

function M.set_last_entry(entry)
  vim.b.rimels_last_entry = entry
end

--- Function to start the Rime language server for the current buffer.
---
--- This function ensures a Rime LS client is attached to the buffer and enables Rime if necessary.
--- It includes a recursive retry mechanism to handle initial attachment issues.
---
--- @param iters? number: Current iteration count for retries (defaults to 0).
--- @return nil
function M.start_rime_ls(iters)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = M.buf_get_rime_ls_client(bufnr)

  if not client then
    -- Attach the Rime LS client to the buffer if not already attached
    M.buf_attach_rime_ls(bufnr)
    -- Retry mechanism to ensure input method takes effect on first start
    iters = iters or 0
    if iters <= 10 then
      vim.schedule(function()
        M.start_rime_ls(iters + 1)
      end)
    end
    return
  end

  -- Enable Rime globally if not already enabled
  if not M.global_rime_enabled() then
    M.toggle_rime(client)
  end

  -- Enable Rime for the buffer if not already enabled
  if not M.buf_rime_enabled() then
    M.buf_toggle_rime(bufnr, true)
  end
end

--- Toggles the Rime input method status via language server command
---
--- This function communicates with the rime_ls language server to toggle
--- the Rime input method state and updates the global status variable.
---
--- @param client table|nil The rime_ls LSP client instance. If nil, attempts to retrieve automatically
--- @param synchronously boolean|nil If true, executes immediately; if false/nil, schedules for next event loop
--- @return nil
function M.toggle_rime(client, synchronously)
  -- Retrieve client if not provided, with fallback to buffer-specific client
  client = client or M.buf_get_rime_ls_client()

  -- Validate client exists and is the correct rime_ls instance
  if not client or client.name ~= "rime_ls" then
    vim.notify("No valid rime_ls client available", vim.log.levels.WARN)
    return
  end

  -- Define the toggle operation with improved error handling
  local function execute_toggle_request()
    client:request(
      "workspace/executeCommand",
      { command = "rime-ls.toggle-rime" },
      function(err, result, ctx, _)
        -- Handle request errors
        if err then
          vim.notify(
            "Failed to toggle Rime: " .. tostring(err),
            vim.log.levels.ERROR
          )
          return
        end

        -- Update global status only for the correct client and valid result
        if ctx.client_id == client.id and result ~= nil then
          vim.api.nvim_set_var(global_rime_status, true)
        else
          vim.api.nvim_set_var(global_rime_status, false)
        end
      end
    )
  end

  -- Execute the toggle request either synchronously or asynchronously
  if synchronously then
    execute_toggle_request()
  else
    vim.schedule(execute_toggle_request)
  end
end

return M
