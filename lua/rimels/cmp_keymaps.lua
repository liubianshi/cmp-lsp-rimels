local utils = require "rimels.utils"

local M = { keymaps = utils.get_mappings() }

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
    local filetype =
        vim.api.nvim_get_option_value("filetype", { scope = "local" })

    if not filetype or filetype == "" then
      return false
    end

    if
        detect_english_env.with_treesitter[filetype]
        and detect_english_env.with_treesitter[filetype](info)
    then
      return true
    end

    if
        detect_english_env.with_syntax[filetype]
        and detect_english_env.with_syntax[filetype](info)
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
    return rc.not_toggle
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
  if not utils.buf_rime_enabled() then
    return
  end
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
  if not utils.global_rime_enabled() and char_after:match "[!-~]" then
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
for numkey = 1, 9 do
  local numkey_str = tostring(numkey)
  M.keymaps[numkey_str] = utils.generate_mapping(function(_)
    if not utils.buf_rime_enabled() then
      return utils.fallback(numkey_str)
    end
    if not utils.is_cmp_visible() then
      if utils.global_rime_enabled() then
        utils.toggle_rime(utils.buf_get_rime_ls_client(), true)
      end
      return utils.fallback(numkey_str)
    end
    utils.feedkey(numkey_str, "n")
    return utils.cmp_without_processing()
  end)
end

-- <Space> -------------------------------------------------------------- {{{3
M.keymaps["<Space>"] = utils.generate_mapping(function(_)
  pcall(vim.api.nvim_buf_del_var, 0, "rimels_last_entry")
  if not utils.is_cmp_visible() then
    M.autotoggle_space()
    return utils.fallback("<Space>")
  end

  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()

  if select_entry then
    if utils.is_rime_entry(select_entry) then
      utils.cmp_confirm(false)
    else
      M.autotoggle_space()
      return utils.fallback("<Space>")
    end
  end

  if M.input_method_take_effect(first_entry) then
    local new_result = utils.adjust_for_rimels(first_entry)
    if new_result then
      first_entry.label = new_result
      if first_entry and first_entry.textEdit then
        first_entry.textEdit.newText = new_result
      end
    end
    utils.set_last_entry(first_entry)
    return utils.cmp_confirm(true)
  end

  M.autotoggle_space()
  return utils.fallback("<Space>")
end)

-- <CR> ----------------------------------------------------------------- {{{3
M.keymaps["<CR>"] = utils.generate_mapping(function(_)
  if not utils.is_cmp_visible() then
    return utils.fallback("<CR>")
  end

  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return utils.fallback("<CR>")
  end

  if M.input_method_take_effect(entry, "all") then
    if M.in_english_environment() then
      utils.toggle_rime()
    end
    utils.cmp_close()
    utils.feedkey(" ", "n")
  elseif
      select_entry
      and utils.get_cmp_source_name(select_entry) ~= "nvim_lsp_signature_help"
  then
    return utils.cmp_confirm(true)
  else
    return utils.cmp_close()
  end

  return utils.cmp_without_processing()
end)

-- [: 实现 rime 选词定字，选中词的第一个字 ------------------------------ {{{3
M.keymaps["["] = utils.generate_mapping(function(_)
  if not utils.is_cmp_visible() then
    return utils.fallback("[")
  end

  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return utils.fallback("[")
  end

  if M.input_method_take_effect(entry) then
    local text = utils.get_cmp_result(entry)
    text = vim.fn.split(text, "\\zs")[1]
    utils.cmp_close()
    vim.schedule(function()
      local input =
          utils.get_input_code(entry):gsub("[^\1-\127]*([\1-\127]+)$", "%1")
      vim.api.nvim_put({ text }, "c", true, true)
      utils.feedkey("<left>", "n")
      for _ = 1, input:len() do
        utils.feedkey("<bs>", "n")
      end
      utils.feedkey("<right>", "n")
    end)
  else
    return utils.fallback("[")
  end

  return utils.cmp_without_processing()
end)

-- ]: 实现 rime 选词定字，选中词的最后一个字 ------------------------------ {{{3
M.keymaps["]"] = utils.generate_mapping(function(_)
  if not utils.is_cmp_visible() then
    return utils.fallback("]")
  end

  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return utils.fallback("]")
  end

  if M.input_method_take_effect(entry) then
    local text = utils.get_cmp_result(entry)
    text = vim.fn.split(text, "\\zs")
    text = text[#text]
    utils.cmp_close()

    vim.schedule(function()
      local input =
          utils.get_input_code(entry):gsub("[^\1-\127]*([\1-\127]+)$", "%1")
      vim.api.nvim_put({ text }, "c", true, true)
      utils.feedkey("<left>", "n")
      for _ = 1, input:len() do
        utils.feedkey("<bs>", "n")
      end
      utils.feedkey("<right>", "n")
    end)
  else
    return utils.fallback("]")
  end

  return utils.cmp_without_processing()
end)

-- <bs> ----------------------------------------------------------------- {{{3
M.keymaps["<BS>"] = utils.generate_mapping(function(_)
  if not utils.is_cmp_visible() then
    local re = M.autotoggle_backspace()
    if re == 1 then
      utils.cmp_close()
      utils.feedkey("<left>", "n")
    else
      return utils.fallback("<BS>")
    end
  else
    return utils.fallback("<BS>")
  end

  return utils.cmp_without_processing()
end)

function M:launch(disable)
  local mappings = utils.filter_cmp_keymaps(self.keymaps, disable or {})
  if not next(mappings) then
    return
  end

  vim.api.nvim_create_autocmd("InsertEnter", {
    callback = function()
      if not require("blink.cmp.config").enabled() then
        return
      end
      utils.blink_apply_keymap(mappings)
    end,
  })

  if
      vim.api.nvim_get_mode().mode == "i"
      and require("blink.cmp.config").enabled()
  then
    utils.blink_apply_keymap(mappings)
  end

  return mappings
end

return M
