local cmp         = require "cmp"
local cmp_config  = require('cmp.config').get()
local utils       = require "rimels.utils"
local langs_not_support_named_parameters = {
  "bash", "sh", "lua", "perl", "vim"
}
local feedkey = function(key, mode)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, true, true),
    mode,
    true
  )
end

local get_input_code = function(entry)
  return entry.completion_item.filterText
end

local get_cmp_result = function(entry)
    return entry.completion_item.textEdit.newText
end

local M = {keymaps = cmp_config.mapping}
function M:set_probes_detects(probes, detectors)
  function self.passed_all_probes(probes_ignored)
    if probes_ignored and probes_ignored == "all" then
      return true
    end
    probes_ignored = probes_ignored or {}
    for name, probe in pairs(probes) do
      if vim.fn.index(probes_ignored, name) < 0 and probe() then
        return false
      end
    end
    return true
  end

  function self.in_english_environment()
    local detect_english_env = detectors
    local info = vim.inspect_pos()
    local filetype = vim.api.nvim_buf_get_option(0, 'filetype')

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
  if
    entry.source.name == "nvim_lsp"
    and entry.source.source.client.name == "rime_ls"
    and M.passed_all_probes(probes_ignored)
  then
    if get_input_code(entry) == get_cmp_result(entry) then return false end
    return true
  else
    return false
  end
end

local function is_rime_entry(entry)
  return entry ~= nil
    and vim.tbl_get(entry, "source", "name") == "nvim_lsp"
    and vim.tbl_get(entry, "source", "source", "client", "name") == "rime_ls"
    and get_input_code(entry) ~= get_cmp_result(entry)
end

function M.rimels_auto_upload(entries)
  if entries == nil or #entries == 0 then
    return nil
  end

  local find_rime_entry = false
  for _, entry in ipairs(entries) do
    if not find_rime_entry then
      find_rime_entry = is_rime_entry(entry)
      cmp.select_next_item {
        behavior = cmp.SelectBehavior.Select,
      }
    else
      if is_rime_entry(entry) then
        return nil
      end
    end
  end

  if find_rime_entry then
    cmp.confirm { behavior = cmp.ConfirmBehavior.Insert }
  end
end

-- number --------------------------------------------------------------- {{{3
M.keymaps["<F31>"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    return fallback()
  end

  if not utils.buf_rime_enabled() then
    return nil
  end

  M.rimels_auto_upload(cmp.core.view:get_entries())
end, { "i" })

for numkey = 1, 9 do
  local numkey_str = tostring(numkey)
  M.keymaps[numkey_str] = cmp.mapping(function(fallback)
    if not cmp.visible() or not utils.buf_rime_enabled() then
      return fallback()
    else
      local first_entry = cmp.core.view:get_first_entry()
      if
        not M.input_method_take_effect(
          first_entry,
          { "probe_punctuation_after_half_symbol" }
        )
      then
        return fallback()
      end
    end
    cmp.mapping.close()
    feedkey(numkey_str, "n")
    cmp.complete()
    feedkey("<F31>", "m")
  end, { "i" })
end

-- <Space> -------------------------------------------------------------- {{{3
M.keymaps["<Space>"] = cmp.mapping(function(fallback)
  pcall(vim.api.nvim_buf_del_var, 0, 'rimels_last_entry')
  if not cmp.visible() then
    M.autotoggle_space()
    return fallback()
  end
  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()

  if select_entry then
    if
      select_entry.source.name == "nvim_lsp"
      and select_entry.source.source.client.name == "rime_ls"
    then
      cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = false }
    elseif
      select_entry.source.name == "nvim_lsp_signature_help"
      and vim.fn.index(langs_not_support_named_parameters, vim.bo.filetype) >= 0
    then
      return fallback()
    else
      cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = false }
      vim.fn.feedkeys " "
    end
  elseif M.input_method_take_effect(first_entry) then
    -- 临时解决 * 和 [ 被错误吃掉的问题
    local input_code = get_input_code(first_entry)
    local cmp_result = get_cmp_result(first_entry)
    local special_symbol_pattern = '[`*%[%]{}]'
    local other_symbol_pattern   = '[^`*%[%]{}]'
    if input_code:match(special_symbol_pattern .. ".") then
      local pattern = string.format("^(.*%s)%s+$", special_symbol_pattern, other_symbol_pattern)
      local prefix = input_code:gsub(pattern, "%1")
      if prefix:sub(1,1) == prefix:sub(2,2) and prefix:sub(1,1):match(special_symbol_pattern)
      then
        prefix = prefix:sub(2)
      end
      first_entry.completion_item.textEdit.newText = prefix .. cmp_result
    end
    vim.api.nvim_buf_set_var(0, 'rimels_last_entry', {input = input_code, cmp = cmp_result})
    cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = true }
  else
    M.autotoggle_space()
    return fallback()
  end
end, { "i", "s" })

-- <CR> ----------------------------------------------------------------- {{{3
M.keymaps["<CR>"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    return (fallback())
  end

  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return (fallback())
  end

  if M.input_method_take_effect(entry, "all") then
    if M.in_english_environment() then
      utils.toggle_rime()
    end
    cmp.abort()
    vim.fn.feedkeys(" ", "n")
  elseif select_entry then
    cmp.confirm()
  else
    fallback()
  end
end, { "i", "s" })

-- [: 实现 rime 选词定字，选中词的第一个字 ------------------------------ {{{3
M.keymaps["["] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    return (fallback())
  end

  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return (fallback())
  end

  if M.input_method_take_effect(entry) then
    local text = entry.completion_item.textEdit.newText
    text = vim.fn.split(text, "\\zs")[1]
    cmp.abort()
    vim.cmd [[normal diw]]
    vim.api.nvim_put({ text }, "c", true, true)
  elseif select_entry then
    cmp.confirm()
  else
    fallback()
  end
end, { "i", "s" })

-- ]: 实现 rime 选词定字，选中词的最后一个字 ------------------------------ {{{3
M.keymaps["]"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    return (fallback())
  end

  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return (fallback())
  end

  if M.input_method_take_effect(entry) then
    local text = entry.completion_item.textEdit.newText
    text = vim.fn.split(text, "\\zs")
    text = text[#text]
    cmp.abort()
    vim.cmd [[normal diw]]
    vim.api.nvim_put({ text }, "c", true, true)
  elseif select_entry then
    cmp.confirm()
  else
    fallback()
  end
end, { "i", "s" })

-- <bs> ----------------------------------------------------------------- {{{3
M.keymaps["<BS>"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    local re = M.autotoggle_backspace()
    if re == 1 then
      cmp.abort()
      local bs = vim.api.nvim_replace_termcodes("<left>", true, true, true)
      vim.api.nvim_feedkeys(bs, "n", false)
    else
      fallback()
    end
  else
    fallback()
  end
end, { "i", "s" })

return M
