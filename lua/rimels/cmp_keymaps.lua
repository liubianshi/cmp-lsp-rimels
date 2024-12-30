local utils       = require "rimels.utils"
local default_opts = require "rimels.default_opts"
local punctuation_upload_directly = default_opts.punctuation_upload_directly

local M = {keymaps = utils.get_mappings()}

---@class Keymap_setup_opts
---@field detectors table
---@field probes table
---@param opts Keymap_setup_opts
function M:setup(opts)
  function self.passed_all_probes(probes_ignored)
    if probes_ignored and probes_ignored == "all" then
      return true
    end
    probes_ignored = probes_ignored or {}
    for name, probe in pairs(opts.probes) do
      if not vim.tbl_contains(probes_ignored, name) and probe() then
        return false
      end
    end
    return true
  end

  function self.in_english_environment()
    local detect_english_env = opts.detectors
    local info = vim.inspect_pos()
    local filetype = vim.api.nvim_get_option_value("filetype", {scope = "local"})

    if not filetype or filetype == "" then
      return false
    end

    if
      detect_english_env.with_treesitter[filetype] and
      detect_english_env.with_treesitter[filetype](info)
    then
      return true
    end

    if
      detect_english_env.with_syntax[filetype] and
      detect_english_env.with_syntax[filetype](info)
    then
      return true
    end

    return false
  end

  return self
end

function M.autotoggle_backspace()
  local rc = { not_toggle = 0, toggle_off = 1, toggle_on = 2 }
  if not utils.buf_rime_enabled() or M.in_english_environment() then
    return rc.NOT_TOGGLE
  end

  -- 只有在删除空格时才启用输入法切换功能
  local word_before_1 = utils.get_chars_before_cursor(1)
  if not word_before_1 or word_before_1 ~= " " then
    return rc.not_toggle
  end

  -- 删除连续空格或行首空格时不启动输入法切换功能
  local word_before_2 = utils.get_chars_before_cursor(2)
  if not word_before_2 or word_before_2 == " " then
    return rc.not_toggle
  end

  -- 删除的空格前是一个空格分隔的 WORD ，或者处在英文输入环境下时，
  -- 切换成英文输入法
  -- 否则切换成中文输入法
  if utils.is_typing_english(1) then
    if utils.global_rime_enabled() then
      utils.toggle_rime()
    end
    return rc.toggle_off
  else
    if not utils.global_rime_enabled() then
      utils.toggle_rime()
    end
    return rc.toggle_on
  end
end

function M.autotoggle_space()
  if not utils.buf_rime_enabled() then return end
  local rc = { not_toggle = 0, toggle_off = 1, toggle_on = 2 }
  if not utils.buf_rime_enabled() or M.in_english_environment() then
    return rc.not_toggle
  end

  -- 行首输入空格或输入连续空格时不考虑输入法切换
  local word_before = utils.get_chars_before_cursor(1)
  if not word_before or word_before == " " then
    return rc.not_toggle
  end

  -- 在英文输入状态下，如果光标后为英文符号，则不切换成中文输入状态
  -- 例如：(abc|)
  local char_after = utils.get_chars_after_cursor(1)
  if not utils.global_rime_enabled() and char_after:match("[!-~]") then
    return rc.not_toggle
  end

  -- 最后一个字符为英文字符，数字或标点符号时，切换为中文输入法
  -- 否则切换为英文输入法
  if word_before:match "[%w%p]" then
    if not utils.global_rime_enabled() then
      utils.toggle_rime()
    end
    return rc.toggle_on
  else
    if utils.global_rime_enabled() then
      utils.toggle_rime()
    end
    return rc.toggle_off
  end
end

function M.input_method_take_effect(entry, probes_ignored)
  if not entry then
    return false
  end

  if not M.passed_all_probes then
    vim.notify(
      "Need rume require('rime.cmp_keympas').set_probes() fisrt",
      vim.log.levels.ERROR
    )
  end
  if utils.is_rime_entry(entry) and M.passed_all_probes(probes_ignored) then
    return true
  else
    return false
  end
end

-- number --------------------------------------------------------------- {{{3
for numkey = 0, 9 do
  local numkey_str = tostring(numkey)
  M.keymaps[numkey_str] = utils.generate_mapping(function(fallback)
    if not utils.is_cmp_visible() or not utils.buf_rime_enabled() then
      return utils.fallback(fallback)
    end

    -- close the cmp menu when 0 is pressed and all entries are from rime-ls
    if numkey == 0 then
      utils.fallback(fallback, "0")
      vim.schedule(function()
        local entries = utils.get_entries()
        for _, entry in ipairs(entries) do
          if not utils.is_rime_entry(entry) then
            return
          end
        end
        utils.cmp_close()
      end)
      return utils.cmp_without_processing()
    end

    utils.feedkey(numkey_str, "n")
    vim.schedule(function()
      if not utils.is_cmp_visible() then return end
      local entries = utils.get_entries() or {}
      local rime_entry_id = utils.get_rime_entry_ids(entries, {only = true})
      if rime_entry_id then
        utils.cmp_select_nth(rime_entry_id)
      end
    end)
    return utils.cmp_without_processing()
  end, { "i" })
end

-- <symbol> ------------------------------------------------------------- {{{3
for _, symbol in ipairs(punctuation_upload_directly) do
  M.keymaps[symbol] = utils.generate_mapping(function(fallback)
    if not utils.buf_rime_enabled() or utils.is_cmp_visible() then
      return utils.fallback(fallback)
    end

    utils.feedkey(symbol, "n")
    -- dd(utils.fallback(fallback, symbol)

    vim.schedule(function()
      if not utils.is_cmp_visible() then return end
      local entries = utils.get_entries()
      utils.cmp_confirm_punction(entries)
    end)

    return utils.cmp_without_processing()
  end)
end

-- <Space> -------------------------------------------------------------- {{{3
M.keymaps["<Space>"] = utils.generate_mapping(function(fallback)
  pcall(vim.api.nvim_buf_del_var, 0, 'rimels_last_entry')
  if not utils.is_cmp_visible() then
    M.autotoggle_space()
    return utils.fallback(fallback)
  end
  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()

  if select_entry then
    if
      utils.is_rime_entry(select_entry)
    then
      utils.cmp_confirm(false)
    else
      return utils.fallback(fallback)
    end
  end

  if M.input_method_take_effect(first_entry) then
    local input_code = utils.get_input_code(first_entry)
    local cmp_result = utils.get_cmp_result(first_entry)
    -- 临时解决 * 和 [ 被错误吃掉的问题，会跟随 rime-ls 的更新调整
    local special_symbol_pattern = '[%[%]{}]'
    local other_symbol_pattern   = '[^%[%]{}]'
    if input_code:match(special_symbol_pattern .. '[A-Za-z]') then
      local pattern = string.format("^.*(%s)%s+$", special_symbol_pattern, other_symbol_pattern)
      local prefix = input_code:gsub(pattern, "%1")
      if prefix:sub(1,1) == prefix:sub(2,2) and prefix:sub(1,1):match(special_symbol_pattern)
      then
        prefix = prefix:sub(2)
      end
      local new_entry = utils.transform_result(first_entry, prefix .. cmp_result)
      if new_entry then
        first_entry = new_entry
      end
    end
    utils.set_last_entry(first_entry)
    return utils.cmp_confirm(true)
  end

  M.autotoggle_space()
  return utils.fallback(fallback)
end, { "i", "s" })

-- <CR> ----------------------------------------------------------------- {{{3
M.keymaps["<CR>"] = utils.generate_mapping(function(fallback)
  if not utils.is_cmp_visible() then
    return utils.fallback(fallback)
  end

  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return utils.fallback(fallback)
  end

  if M.input_method_take_effect(entry, "all") then
    if M.in_english_environment() then
      utils.toggle_rime()
    end
    utils.cmp_close()
    utils.feedkey(" ", "n")
  elseif select_entry and utils.get_cmp_source_name(select_entry) ~= "nvim_lsp_signature_help" then
    return utils.cmp_confirm(true)
  else
    return utils.cmp_close()
  end

  return utils.cmp_without_processing()
end, { "i", "s" })

-- [: 实现 rime 选词定字，选中词的第一个字 ------------------------------ {{{3
M.keymaps["["] = utils.generate_mapping(function(fallback)
  if not utils.is_cmp_visible() then
    return utils.fallback(fallback)
  end

  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return utils.fallback(fallback)
  end

  if M.input_method_take_effect(entry) then
    local text = utils.get_cmp_result(entry)
    text = vim.fn.split(text, "\\zs")[1]
    utils.cmp_abort()
    vim.schedule(function()
      local input = utils.get_input_code(entry):gsub("[^\1-\127]*([\1-\127]+)$", "%1")
      vim.api.nvim_put({ text }, "c", true, true)
      utils.feedkey("<left>", "n")
      for _ = 1, input:len() do
        utils.feedkey("<bs>", "n")
      end
      utils.feedkey("<right>", "n")
    end)
  else
    return utils.fallback(fallback)
  end

  return utils.cmp_without_processing()
end, { "i", "s" })

-- ]: 实现 rime 选词定字，选中词的最后一个字 ------------------------------ {{{3
M.keymaps["]"] = utils.generate_mapping(function(fallback)
  if not utils.is_cmp_visible() then
    return utils.fallback(fallback)
  end

  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return utils.fallback(fallback)
  end

  if M.input_method_take_effect(entry) then
    local text = utils.get_cmp_result(entry)
    text = vim.fn.split(text, "\\zs")
    text = text[#text]
    utils.cmp_abort()

    vim.schedule(function()
      local input = utils.get_input_code(entry):gsub("[^\1-\127]*([\1-\127]+)$", "%1")
      vim.api.nvim_put({ text }, "c", true, true)
      utils.feedkey("<left>", "n")
      for _ = 1, input:len() do
        utils.feedkey("<bs>", "n")
      end
      utils.feedkey("<right>", "n")
    end)
  else
    return utils.fallback(fallback)
  end

  return utils.cmp_without_processing()
end, { "i", "s" })

-- <bs> ----------------------------------------------------------------- {{{3
M.keymaps["<BS>"] = utils.generate_mapping(function(fallback)
  if not utils.is_cmp_visible() then
    local re = M.autotoggle_backspace()
    if re == 1 then
      utils.cmp_abort()
      utils.feedkey("<left>", "n")
    else
      return utils.fallback(fallback)
    end
  else
    return utils.fallback(fallback)
  end

  return utils.cmp_without_processing()
end, { "i", "s" })

return M
