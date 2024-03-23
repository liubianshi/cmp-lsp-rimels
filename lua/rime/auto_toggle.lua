local utils = require('rime.utils')
local rc = { not_toggle = 0, toggle_off = 1, toggle_on =  2 }
local M = {}

function M.backspace()
    if not utils.buf_rime_enabled() or utils.in_english_environment() then
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
        vim.cmd("ToggleRime off")
        return rc.toggle_off
    else
        vim.cmd("ToggleRime on")
        return rc.toggle_on
    end
end

function M.space()
    if not utils.buf_rime_enabled() or utils.in_english_environment() then
        return rc.NOT_TOGGLE
    end

    -- 行首输入空格或输入连续空格时不考虑输入法切换
    local word_before = utils.get_chars_before_cursor(1)
    if not word_before or word_before == " " then
        return rc.not_toggle
    end

    -- 最后一个字符为英文字符，数字或标点符号时，切换为中文输入法
    -- 否则切换为英文输入法
    if word_before:match("[%w%p]") then
        vim.cmd("ToggleRime on")
        return rc.toggle_on
    else
        vim.cmd("ToggleRime off")
        return rc.toggle_off
    end
end

return M
