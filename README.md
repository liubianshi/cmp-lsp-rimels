# cmp-lsp-rimels

`cmp-lsp-rimels` 是 [wlh320/rime-ls][2] 在 Neovim 下的一个配置方案，通过减少大量
输入法手动切换场景，优化来 Neovim 下的中文输入，特别是中英文混合输入的体验。项
目的设计在很多方面受到了 [DogLooksGood/emacs-rime][3] 启发。

https://github.com/liubianshi/cmp-lsp-rimels/assets/24829102/f6d76a3e-3712-4736-a39f-1870b2bcec30

项目的测试目前严重不足，几乎全部来自本人在 MacOS 和 ArchLinux 上的日常使用（从
[#1][8] 看配置在 Windows 下应该也能运行），因此请保持警惕，最好只将之视为自己
配置 [wlh320/rime-ls][2] 的参考。

## 特点

- 速度极快，输入法状态的自动切换（包括插入模式和普通模式转变时的切换，插入模式
  下中英文输入的切换）不会产生时滞

- 流畅，在多数情况下，无需手动切换输入法，即可实现中英文混合输入，也能够在数学
  公式、代码等特殊环境半自动地临时关闭输入法（在按 `<enter>`后）。

- 不会干扰插入模式下 keymap，例如，默认情况下，可在插入模式下，用 `;f` 切换到中文
  输入状态，`;;`切换到英文输入状态, `;j` 切换到普通模式。在系统输入法下，就很难实现
  使用 `jk` 退出插入模式

- 能够使用常规输入法的部分功能，主要依靠 [wlh320/rime-ls][2]，这里增加了数字键
  选中候选词并直接上屏，通过 `[` 和 `]` 实现以词定字等，并采用临时方案解决了上游的
  一些问题, 如 [用数字选词以后还需要一次空格才能上屏幕][5]，[字符补全后消失][4]

- 在各种 Buffer 下均可启用，且通常情况不会意外开启

- 具有一定的可扩展性，比如控制两类探针的使用，一类用于判定当前是否处在英文输入
  环境，一类用于判定是否让候选词上屏，详见 [配置](README# 配置)（目前文档还不
  完整）

## 依赖

- [wlh320/rime-ls][2]: A language server for Rime input method engine
- [hrsh7th/nvim-cmp][1]: A completion plugin for neovim coded in Lua.
- [hrsh7th/cmp-nvim-lsp][6]: nvim-cmp source for neovim builtin LSP client
- [neovim/nvim-lspconfig][7]: Quickstart configs for Nvim LSP

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

## 思路

核心思路是修改空格的行为，让它根据当前场景决定自动切换到中文或英文输入状态，根
据前后文决定是否将候选词上屏等。

`cmp-lsp-rimels` 的功能高度依赖在中英文之间插入空格的习惯。当您在中文字符后面输入
一个空格时，它会认为您接下来想输入的时英文，并自动切换到中文输入法，在您输入法
完英文后，再按空格，那么它会主动将输入法切换回中文输入状态。如果您习惯中英文连
排，那么 `cmp-lsp-rimels` 可能对您并不合适，不仅输入法自动切换的功能将失效，而且
可能出现奇怪的 Bug.

如果希望输入多个英文字符呢？多数情况下，需要我们手动切换到英文输入法，除非，您
的光标后面有一个半角字符。比如输入 `cmp and rime-ls` 这几个单词，如何有成对括号自
动补全的插件的情况，是无须手动切换中英文输入状态的。

至于决定是否上屏候选词，最初设计的目的是应对在一些时候，我们需要在中文输入法的
状态下，直接输入英文标点符号。比如，在编辑 markdown 文件时，我们经常需要在行首
输入 `-`. 

采用类似的思路，`<backspace>` 键也被做了一定的修改，主要实现的功能是在删除空格时根
据前面的字符自动切换输入法。如果前面的字符是英文，那么会将输入法切换到英文输入
状态，如果删除空格后光标前面的字符是中文字符，那么它会将输入法切换到中文状态。

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







<!-- Links -->
[1]: https://github.com/hrsh7th/nvim-cmp
[2]: https://github.com/wlh320/rime-ls
[3]: https://github.com/DogLooksGood/emacs-rime
[4]: https://github.com/wlh320/rime-ls/issues/10#issuecomment-1627661945
[5]: https://github.com/wlh320/rime-ls/issues/20
[6]: https://github.com/hrsh7th/cmp-nvim-lsp
[7]: https://github.com/neovim/nvim-lspconfig
[8]: https://github.com/liubianshi/cmp-lsp-rimels/issues/1
