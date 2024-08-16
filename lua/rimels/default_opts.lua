local M = {
  filetypes = { 'NO_DEFAULT_FILETYPES' },
  cmd = { "/sbin/rime_ls" },
  single_file_support = true,
  settings = {},
  rime_user_dir = "~/.local/share/rime-ls",
  shared_data_dir = "/usr/share/rime-data",
  paging_characters = {",", ".", "-", "="},
  trigger_characters = {},
  always_incomplete = false,
  docs = {
    description = [[https://www.github.com/wlh320/rime-ls, A language server for librime]],
  },
  keys = {
    start = ";f",
    stop = ";;",
    esc = ";j",
    undo = ";u",
  },
  max_candidates = 9,
  schema_trigger_character = "&", -- [since v0.2.0] 当输入此字符串时请求补全会触发 “方案选单”
  probes = {
    ignore = {},
    using = {},
    add = {},
  },
  detectors = {
    with_treesitter = {},
    with_syntax = {},
  },
  punctuation_upload_directly = {",", ".", ":", "\\", "?", "!"},
  cmp_keymaps = {
    disable = {
      space     = false,
      numbers   = false,
      enter     = false,
      brackets  = false,
      backspace = false,
      punctuation_upload_directly = false,
    }
  },
}

if vim.fn.has "mac" == 1 then
  M.shared_data_dir =
    "/Library/Input Methods/Squirrel.app/Contents/SharedSupport"
  M.cmd = { vim.env.HOME .. "/.local/bin/rime_ls" }
end

return M
