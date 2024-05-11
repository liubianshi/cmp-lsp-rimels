local utils = require "rimels.utils"
local M = {}
local PASS = false
local REJECT = true

function M.probe_temporarily_disabled()
  if utils.buf_rime_enabled() then
    return PASS
  else
    return REJECT
  end
end

function M.caps_start()
  if utils.get_content_before_cursor():match "[A-Z][%w]*%s*$" then
    return REJECT
  else
    return PASS
  end
end

function M.probe_punctuation_after_half_symbol()
  local content_before = utils.get_content_before_cursor(1) or "";
  local word_pre1 = utils.get_chars_before_cursor(1, 1)
  local word_pre2 = utils.get_chars_before_cursor(2, 1)
  if not (word_pre1 and word_pre1:match "[-%p]") then
    return PASS
  elseif
    not word_pre2 or word_pre2 == ""
    or word_pre2:match('[-%s%p]')
    or (word_pre2:match('%w') and content_before:match('%s%w+$'))
    or (word_pre2:match('%w') and content_before:match('^%w+$'))
  then
    return REJECT
  else
    return PASS
  end
end

function M.probe_in_mathblock()
  local info = vim.inspect_pos()
  for _, syn in ipairs(info.syntax) do
    if syn.hl_group_link:match "mathblock" then
      return REJECT
    end
  end
  for _, ts in ipairs(info.treesitter) do
    if ts.capture == "markup.math" then
      return REJECT
    end
  end
  return PASS
end

return M
