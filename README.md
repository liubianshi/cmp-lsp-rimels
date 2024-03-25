# cmp-lsp-rimels

https://github.com/liubianshi/cmp-lsp-rimels/assets/24829102/f6d76a3e-3712-4736-a39f-1870b2bcec30


`cmp-lsp-rimels` 的目标是优化 Neovim 下的中文输入体验，特别是中英文混合输入时的体验。

## 特点

- 在多数情况下，无需手动切换输入法，即可实现中英文混合输入
- 流畅，输入法状态的自动切换（包括插入模式和普通模式转变时的切换，插入模式下中英文输入的切换）不会产生时滞
- 不会干扰插入模式下的快捷方式，比如默认情况下，在插入模式下，可用 `;f` 切换到中文输入状态，`;;` 切换到英文输入状态, `;j` 切换到普通模式
- 能够使用常规输入法的很多功能，比如数字键选中候选词并直接上屏，通过 `[` 和 `]` 实现以词定字等
- 配置简单
- 具有一定的可扩展性，比如两类探针，一类用于判定当前是否处在英文输入环境，一类用于判定是否让候选词上屏，详见 [${1:配置}](README#配置)

## 依赖

- [wlh320/rime-ls](https://github.com/wlh320/rime-ls): A language server for Rime input method engine
- [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp): A completion plugin for neovim coded in Lua.
- [hrsh7th/cmp-nvim-lsp](https://github.com/hrsh7th/cmp-nvim-lsp): nvim-cmp source for neovim builtin LSP client
- [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig): Quickstart configs for Nvim LSP

## 安装

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "liubianshi/cmp-lsp-rimels",
  opts = {
    -- your configuration comes here
    -- or leave it empty to use the default settings
    -- refer to the configuration section below
  },
}
```

## 配置

默认选项：

```lua
{
  keys = { start = ";f", stop = ";;", esc = ";j" },
  cmd = { "/sbin/rime_ls" }, -- MacOS: ~/.local/bin/rime_ls
  rime_user_dir = "~/.local/share/rime-ls",
  shared_data_dir = "/usr/share/rime-data", -- MacOS: /Library/Input Methods/Squirrel.app/Contents/SharedSupport
  filetypes = { 'NO_DEFAULT_FILETYPES' },
  single_file_support = true,
  settings = {},
  docs = {
    description = [[https://www.github.com/wlh320/rime-ls, A language server for librime]],
  },
  max_candidates = 9,
  trigger_characters = {},
  schema_trigger_character = "&", -- [since v0.2.0] 当输入此字符串时请求补全会触发 “方案选单”
  probes = {
    ignore = {},
    using = {},
    add = {},
  }
  detects = {
    ignore = {},
    using = {},
    add = {},
  }
}
```

