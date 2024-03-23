local utils = require "rime.utils"
local M = {probes = {}}
local PASS = false
local REJECT = true

function M.probes.probe_temporarily_disabled()
  if utils.buf_rime_enabled() then
    return PASS
  else
    return REJECT
  end
end

function M.probes.caps_start()
  if utils.get_content_before_cursor():match "[A-Z][%w]*%s*$" then
    return REJECT
  else
    return PASS
  end
end

function M.probes.probe_punctuation_after_half_symbol()
  local word_pre1 = utils.get_chars_before_cursor(1, 1)
  local word_pre2 = utils.get_chars_before_cursor(2, 1)
  if not (word_pre1 and word_pre1:match "[-%p]") then
    return PASS
  elseif not word_pre2 or word_pre2 == "" or word_pre2:match "[%w%p%s]" then
    return REJECT
  else
    return PASS
  end
end

function M.probes.probe_in_mathblock()
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

function M.get_probe_names()
  local probe_names = {}
  for name, _ in pairs(M.probes) do
    table.insert(probe_names, name)
  end
  return probe_names
end

function M.probes_all_passed(probes_ignored)
  if probes_ignored and probes_ignored == "all" then
    return true
  end
  probes_ignored = probes_ignored or {}
  for name, probe in pairs(M.probes) do
    if vim.fn.index(probes_ignored, name) < 0 and probe() then
      return false
    end
  end
  return true
end



return M
