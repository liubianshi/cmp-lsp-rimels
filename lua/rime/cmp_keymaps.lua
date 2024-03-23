local cmp         = require "cmp"
local lsp_kinds   = require("cmp.types").lsp.CompletionItemKind
local utils       = require "rime.utils"
local auto_toggle = require "rime.auto_toggle"

local input_method_take_effect = function(entry, probes_ignored)
  if not entry then
    return false
  end

  if
    entry.source.name == "nvim_lsp"
    and entry.source.source.client.name == "rime_ls"
    and utils.probes_all_passed(probes_ignored)
  then
    return true
  else
    return false
  end
end

local rimels_auto_upload = function(entries)
  if #entries == 1 then
    if input_method_take_effect(entries[1]) then
      cmp.confirm {
        behavior = cmp.ConfirmBehavior.Insert,
        select = true,
      }
    end
  end
end

local feedkey = function(key, mode)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, true, true),
    mode,
    true
  )
end

local M = {}

-- number --------------------------------------------------------------- {{{3
M["0"] = cmp.mapping(function(fallback)
  if not cmp.visible() or not utils.buf_rime_enabled() then
    return fallback()
  end

  local first_entry = cmp.core.view:get_first_entry()
  if not input_method_take_effect(first_entry) then
    return fallback()
  end

  rimels_auto_upload(cmp.core.view:get_entries())
end, { "i" })

for numkey = 1, 9 do
  local numkey_str = tostring(numkey)
  M[numkey_str] = cmp.mapping(function(fallback)
    if not cmp.visible() or not utils.buf_rime_enabled() then
      return fallback()
    else
      local first_entry = cmp.core.view:get_first_entry()
      if
        not input_method_take_effect(
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
    feedkey("0", "m")
  end, { "i" })
end

-- <Space> -------------------------------------------------------------- {{{3
M["<Space>"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    auto_toggle.space()
    return fallback()
  end
  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()

  if select_entry then
    if
      select_entry:get_kind()
      and lsp_kinds[select_entry:get_kind()] ~= "Text"
    then
      cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = false }
      vim.fn.feedkeys " "
    else
      cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = false }
    end
  elseif input_method_take_effect(first_entry) then
    cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = true }
  else
    auto_toggle.space()
    return fallback()
  end
end, { "i", "s" })

-- <CR> ----------------------------------------------------------------- {{{3
M["<CR>"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    return (fallback())
  end

  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return (fallback())
  end

  if input_method_take_effect(entry, "all") then
    cmp.abort()
    vim.fn.feedkeys " "
  elseif select_entry then
    cmp.confirm()
  else
    fallback()
  end
end, { "i", "s" })

-- [: 实现 rime 选词定字，选中词的第一个字 ------------------------------ {{{3
M["["] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    return (fallback())
  end

  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return (fallback())
  end

  if input_method_take_effect(entry) then
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
M["]"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    return (fallback())
  end

  local select_entry = cmp.get_selected_entry()
  local first_entry = cmp.core.view:get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return (fallback())
  end

  if input_method_take_effect(entry) then
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
M["<BS>"] = cmp.mapping(function(fallback)
  if not cmp.visible() then
    local re = auto_toggle.backspace()
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
