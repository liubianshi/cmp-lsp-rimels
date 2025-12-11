--- Rimels plugin main module
--- Provides setup and configuration for the rime input method integration
local utils = require "rimels.utils"
local has_setup = false
local M = {}

--- Setup the rimels plugin with provided options
--- @param opts table|nil Configuration options for the plugin
--- @return table The module table for method chaining
function M.setup(opts)
  -- Prevent multiple setup calls
  if has_setup then
    return M
  end
  has_setup = true

  -- Merge user options with defaults
  opts = require("rimels.config").update_option(opts or {})

  -- Initialize rime language server
  utils.rime_ls_setup(opts)

  -- Setup input method toggle keymap
  vim.keymap.set({ "i" }, opts.keys.start, utils.start_rime_ls, {
    silent = true,
    noremap = true,
    desc = "Toggle Input Method",
  })

  -- Initialize and configure completion keymaps
  M.keymaps = require("rimels.cmp_keymaps")
    :setup({
      probes = opts.probes.using,
      detectors = opts.detectors,
    })
    :launch(opts.cmp_keymaps.disable)

  -- Store configuration for later access
  M.opts = opts

  -- Autocmd to enhance Blink completion behavior for numbers and punctuation with Rime
  -- - When Blink shows completion (User BlinkCmpShow), if the last typed character is a number (1-9)
  --   or a configured punctuation, perform a specific action using Rime utilities.
  -- - Adds defensive checks and minimizes redundant lookups for clarity and robustness.

  local api = vim.api

  -- Create or reuse augroup once
  local group = api.nvim_create_augroup("blink.lsp.rimels", { clear = true })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "BlinkCmpShow",
    callback = vim.schedule_wrap(function(event)
      local bufnr = (event and event.buf) or api.nvim_get_current_buf()
      if
        not utils.global_rime_enabled() or not utils.buf_rime_enabled(bufnr)
      then
        return
      end

      -- Extract completion context safely
      local ctx = vim.tbl_get(event or {}, "data", "context")
      if type(ctx) ~= "table" then
        return
      end
      local line = ctx.line
      local cursor = ctx.cursor
      if type(line) ~= "string" or type(cursor) ~= "table" then
        return
      end

      -- Get character at the cursor column (guard indices)
      local col = tonumber(cursor[2])
      if not col or col < 1 or col > #line then
        return
      end
      local ch = line:sub(col, col)
      if ch == "" then
        return
      end

      -- Determine trigger type: number (1-9) or configured punctuation
      local punctuation_list = (opts and opts.punctuation_upload_directly) or {}
      local is_punctuation = vim.tbl_contains(punctuation_list, ch)
      local is_number = not is_punctuation and (ch:match "[1-9]" ~= nil)

      if not (is_number or is_punctuation) then
        return
      end

      -- Retrieve Blink completion items safely
      local ok, cmp = pcall(require, "blink.cmp")
      if not ok or type(cmp.get_items) ~= "function" then
        return
      end
      local items = cmp.get_items()
      if type(items) ~= "table" or #items == 0 then
        return
      end

      -- Execute corresponding action
      vim.schedule(function()
        if is_number then
          local rime_id = utils.get_rime_entry_ids(items, { only = true })
          if rime_id then
            utils.cmp_select_nth(rime_id, items)
          end
        else -- punctuation
          -- Note: function name kept as in original (cmp_confirm_punction)
          utils.cmp_confirm_punction(items)
        end
      end)
    end),
  })

  -- Autocmd to synchronize Rime input method status when entering a buffer
  api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    callback = function(event)
      -- Extract buffer number from event, return early if invalid
      local bufnr = event and event.buf
      if not bufnr then
        return
      end

      -- Ignore special buffers where Rime is not needed
      local buftype = api.nvim_get_option_value("buftype", { buf = bufnr })
      if buftype ~= "" then
        return
      end

      -- Check global and buffer-specific Rime enabled statuses
      local rime_status_global = utils.global_rime_enabled()
      local rime_status_buf = utils.buf_rime_enabled(bufnr)

      -- Toggle Rime if there's a mismatch between global and buffer statuses
      if rime_status_buf ~= rime_status_global then
        utils.toggle_rime()
      end
    end,
  })

  return M
end

--- Public API Functions ---

--- Get the rime_ls LSP client if available
--- @return table|nil The rime_ls client or nil if not found
function M.get_rime_ls_client()
  local clients = vim.lsp.get_clients { name = "rime_ls" }
  return clients[1] -- Return first client or nil if none found
end

return M
