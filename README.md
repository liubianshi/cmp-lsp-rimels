# cmp-lsp-rimels

`cmp-lsp-rimels` 的目标是优化 Neovim 下的中文输入体验，特别是中英文混合输入时的体验。

建立在 [wlh320/rime-ls](https://github.com/wlh320/rime-ls) 的基础上。

深受 [DogLooksGood/emacs-rime](https://github.com/DogLooksGood/emacs-rime) 的启发。

非专业人士的非专业工具，除在 MacOS 和 Arch Linux 上的日常使用外，未做额外的测试。

如决定使用，请务必小心。

https://github.com/liubianshi/cmp-lsp-rimels/assets/24829102/f6d76a3e-3712-4736-a39f-1870b2bcec30

## 特点

- 流畅，输入法状态的自动切换（包括插入模式和普通模式转变时的切换，插入模式下中英文输入的切换）不会产生时滞
- 无感，在多数情况下，无需手动切换输入法，即可实现中英文混合输入，能够在数学公式、代码等特殊环境近乎自动地临时关闭输入法。
- 不会干扰插入模式下 keymap，例如，默认情况下，可在插入模式下，用 `;f` 切换到中文输入状态，`;;` 切换到英文输入状态, `;j` 切换到普通模式
- 能够使用常规输入法的部分功能，主要靠 [wlh320/rime-ls](https://github.com/wlh320/rime-ls)，这里增加了数字键选中候选词并直接上屏，和通过 `[` 和 `]` 实现以词定字等
- 在各种 Buffer 下均可启用，且通常情况不会意外开启
- 具有一定的可扩展性，比如控制两类探针的使用，一类用于判定当前是否处在英文输入环境，一类用于判定是否让候选词上屏，详见 [配置](README#配置)（目前文档还不完整）。


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
  dependencies = {
    'neovim/nvim-lspconfig', 
    'hrsh7th/nvim-cmp',
    'hrsh7th/cmp-nvim-lsp',
  },
  config = function()
    require('rimels').setup({})
  end,
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
  detectors = {
    with_treesitter = {},
    with_syntax = {},
  },
  cmp_keymaps = {
    disable = {
      space     = false,
      numbers   = false,
      enter     = false,
      brackets  = false,
      backspace = false,
    }
  },
}
```

### 禁用 cmp keymaps

在默认情况下，本插件会针对 nvim-cmp 设置几组 Keymaps, 这是本插件发挥作用的关键，所以通常不建议修改。

如果确实有进一步修改按键行为的需求，可以通过 `cmp_keymaps.disable` 选择性禁用。

- `space`, 空格键自动切换输入法, 以及当第一个候选字由 rime_ls 返回时上屏该候选词
- `numbers`, 数字键直接上屏
- `enter`, 回车键放弃补全
- `brackets`, 以词定字  
- `backspace`, 删除键自动切换输入法

例如, 禁用通过 `[` 和 `]` 实现的以词定字功能, 可采用如下设置: 

```lua
{
  cmp_keymaps = {
    disable = {
      brackets = true
    }
  }
}
```







