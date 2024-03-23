local utils = require("rime/utils")
    bufnr = bufnr or vim.api.nvim_get_current_buf()
local M = {}

function M.probe_temporarily_disabled()
	return not vim.b.rime_enabled
end

function M.caps_start()
	return utils.get_content_before_cursor():match("[A-Z][%w]*%s*$")
end

function M.probe_punctuation_after_half_symbol()
	local word_pre1 = utils.get_chars_before_cursor(1, 1)
	local word_pre2 = utils.get_chars_before_cursor(2, 1)
	if not (word_pre1 and word_pre1:match("[-%p]")) then
		return false
	elseif not word_pre2 or word_pre2 == "" or word_pre2:match("[%w%p%s]") then
		return true
	else
		return false
	end
end

function M.probe_in_mathblock()
	local info = vim.inspect_pos()
	for _, syn in ipairs(info.syntax) do
		if syn.hl_group_link:match("mathblock") then
			return true
		end
	end
	for _, ts in ipairs(info.treesitter) do
		if ts.capture == "markup.math" then
			return true
		end
	end
	return false
end

return M
