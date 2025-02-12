# cmp-lsp-rimels

`cmp-lsp-rimels` 是 [wlh320/rime-ls][2] 在 Neovim 下的一个配置方案，可在多数场景实现输入
法自动切换，优化来 Neovim 下的中文输入，特别是中英文混合输入的体验。项目的设计在很
多方面受到了 [DogLooksGood/emacs-rime][3] 启发。

https://github.com/liubianshi/cmp-lsp-rimels/assets/24829102/f6d76a3e-3712-4736-a39f-1870b2bcec30

项目目前不算稳定。测试主要来自本人在 MacOS 和 ArchLinux 上的日常使用，能正常运行。
从 [#1][8] 看项目在 Windows 下应该也能运行。

如果您熟悉 [nvim-cmp][1]、[blink.cmp][9] 和 [wlh320/rime-ls][2]，那么还是建议只将本项目视为自己配
置的参考。

## 特点

- 流畅。输入法的自动切换（包括插入模式和普通模式转变时的切换，插入模式下中英文输入
  的切换）不会产生时滞。此外，在多数情况下，无需手动切换输入法，即可实现中英文混合
  输入。

- 不会干扰插入模式下 keymaps。在使用系统输入法时， `jk` 等退出插入模式之类的 keymap
  会变得很难用，输入法会劫持输入的字母。但在本项目不会有这个问题。

- 能够使用常规输入法的大部分功能。主要得益于 [wlh320/rime-ls][2]，这里增加了数字键选中
  候选词并直接上屏，通过 `[` 和 `]` 实现以词定字, 输入部分标点符号，如 `,` 和 `.` 等，可在
  特定的情形自动上屏。此外，也采用临时方案解决了上游的一些问题, 如 [用数字选词以后
  还需要一次空格才能上屏幕][5]，[字符补全后消失][4]

- 能够使用 `;u` 撤销上屏，并恢复之前输入的字符（目前还有一些 Bug）

- 能够在各种 Buffer 下启用，且通常情况不会意外开启。在常规配置下，[wlh320/rime-ls][2]
  需要在 `lsp` 能自动启用的 buffer 才能生效。本项目可使 `rime-ls` 在所有可开启 cmp
  的 buffer 生效。

- 具有一定的可扩展性，比如控制两类探针的使用，一类用于判定当前是否处在英文输入环境，
  一类用于判定是否让候选词上屏。

## 依赖

- [wlh320/rime-ls][2]
- ([hrsh7th/nvim-cmp][1] + [hrsh7th/cmp-nvim-lsp][6]) / [Saghen/blink.cmp][9]
- [neovim/nvim-lspconfig][7]: Quickstart configs for Nvim LSP

## 安装

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "liubianshi/cmp-lsp-rimels",
  keys = {{"<localleader>f", mode = "i"}},
  branch = "blink.cmp",
  config = function()
    require('rimels').setup({})
  end,
}
```

推荐下面的配置，好处是可以避免开启多个 rime, 以及因此产生的用户词库冲突。

```lua
{
  "liubianshi/cmp-lsp-rimels",
  keys = {{"<localleader>f", mode = "i"}},
  branch = "blink.cmp",
  config = function()
    vim.system({'rime_ls', '--listen', '127.0.0.1:9257'}, {detach = true})
    require('rimels').setup({
      cmd = vim.lsp.rpc.connect("127.0.0.1", 9257),
    })
  end,
}
```

如果使用的补全框架为 [blink.cmp][9], 那么需要在配置 [blink.cmp][9] 时，手动加入 `cmp-lsp-rimels`
的 `kepmaps`，并修改默认的 LSP 过滤规则。

```lua
{
  -- 参考：https://github.com/wlh320/rime-ls/blob/master/doc/nvim-with-blink.md
  sources = {
    -- ...
    providers = {
      lsp = {
        transform_items = function(_, items)
          -- the default transformer will do this
          for _, item in ipairs(items) do
            if item.kind == require('blink.cmp.types').CompletionItemKind.Snippet then
              item.score_offset = item.score_offset - 3
            end
          end
          -- you can define your own filter for rime item
          return items
        end
      }
    },
    -- ...
  }
}
```

此外，`blink.cmp` 的默认 `completion.keyword.regex` 为 `'[-_]\\|\\k'`, 而 `\k` 的默认值为
`@,48-57,_,192-255`, 会导致所有的中文都是有效字符，将我个人体验看，这会严重降低输入
法的响应速度。建议修改 `completion.keyword.regex` 或 `vim.opt.iskeyword`. 由于 `blink.cmp`
目前不能动态设置 `completion.keyword.regex`, 所以我倾向于修改 `iskeyword`.

```lua
vim.opt.iskeyword = "_,49-57,A-Z,a-z"
```

## 思路

核心思路是修改空格的行为，让它根据当前场景决定自动切换到中文或英文输入状态，根据前
后文决定是否将候选词上屏等。

`cmp-lsp-rimels` 的功能高度依赖在中英文之间插入空格的习惯。在中文字符后面按空格时，
会假定随后需要输入的是英文，并自动切换到英文输入法。在完成英文输入后，再按空格，那
么它会主动将输入法切换回中文输入状态。如果您很不习惯中英文之间插入空格，那么
`cmp-lsp-rimels` 可能对您并不合适。这不仅输入法自动切换的功能将失效，而且可能出现奇
怪的 Bug.

如果希望连续英文单词呢？多数情况下，需要我们手动切换到英文输入法，除非，您的光标后
面有一个半角字符。在已自动切换到英文输入状态，且处在 `(|)` 情况下（`|` 为光标位置），
连续输入 `cmp and rime` 时无须手动切换到英文输入法。

采用类似的思路，`<backspace>` 键也被做了一定的修改，主要实现的功能是在删除空格时根
据前面的字符自动切换输入法。如果前面的字符是英文，那么会将输入法切换到英文输入状态，
如果删除空格后光标前面的字符是中文字符，那么它会将输入法切换到中文状态。

## 配置

默认选项：

```lua
{
  keys = { start = ";f", stop = ";;", esc = ";j", undo = ";u" },
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
      punctuation_upload_directly = false,
    }
  },
}
```

### 禁用 cmp keymaps

在默认情况下，本插件会针对 nvim-cmp 设置几组 Keymaps, 这是本插件发挥作用的关键，所
以通常不建议修改。

如果确实有进一步修改按键行为的需求，可以通过 `cmp_keymaps.disable` 选择性禁用。

- `space`, 空格键自动切换输入法, 以及当第一个候选字由 rime_ls 返回时上屏该候选词
- `numbers`, 数字键直接上屏
- `enter`, 回车键放弃补全
- `brackets`, 以词定字
- `backspace`, 删除键自动切换输入法
- `punctuation_upload_directly`, 部分标点符号在候选词只有唯一对应的中文标点符号时直
  接上屏。默认支持 `{",", ".", ":", "\\", "?", "!"}`。设置为 `true` 时，禁用此功能，也
  可以选择禁用部分标点，如 `punctuation_upload_directly = {":", "?"}`

例如, 禁用通过 `[` 和 `]` 实现的以词定字功能, 可采用如下设置 :

```lua
{
  cmp_keymaps = {
    disable = {
      brackets = true
    }
  }
}
```

### 设置 probes

探针的作用在于根据上下文判断是否上屏 rime_ls 返回的候选词。例如，输入 `Ax` 后，
rime_ls 会返回候选词，但因为探针 `probe_caps_start` 的存在，此时按空格不会上屏
rime_ls 的候选词。默认开启的探针包括如下几个：

- `probe_temporarily_disabled`: 是否临时禁用 `rime_ls`
- `probe_caps_start`: 开头是否为大写字母
- `probe_punctuation_after_half_symbol`: 是否在英文字符后面输入标点符号
- `probe_in_mathblock`: 是否正在输入公式

可以通过 `probes.ignore` 禁用部分探针，或者使用 `probes.add` 覆盖旧探针或增加新探针。
`probes.ignore` 接受探针名构成的列表，如 `{"probe_in_mathblock", "probe_caps_start"}`
`probes.add` 接受探针名和探针构成的 Table, 如

```lua
{
  probe_in_mathblock = function()
    local info = vim.inspect_pos()
    for _, syn in ipairs(info.syntax) do
      if syn.hl_group_link:match "mathblock" then
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
}
```

### 设置 detectors

`detector` 接受一个函数，用于判断光标是否处在英文输入环境，比如数学公式中。函数可以
基于 treesitter 或 syntax 判断，需要返回布尔值。可以参考下面的设置。

```lua
local detector_for_norg = function(info)
  info = info or vim.inspect_pos()
  local trees = info.treesitter
  local extmarks = info.extmarks
  local englist_env = false
  for _, ts in ipairs(trees) do
    if
      ts.capture == "neorg.markup.variable"
      or ts.capture == "neorg.markup.verbatim"
      or ts.capture == "neorg.markup.inline_math"
    then
      return true
    elseif ts.capture == "comment" then
      return false
    end
  end
  for _, ext in ipairs(extmarks) do
    if
      ext.opts
      and ext.opts.hl_group == "@neorg.tags.ranged_verbatim.code_block"
    then
      return true
    end
  end
  return englist_env
end

{
  "liubianshi/cmp-lsp-rimels",
  keys = {{"<localleader>f", mode = "i"}},
  config = function()
    vim.system({'rime_ls', '--listen', '127.0.0.1:9257'}, {detach = true})
    require('rimels').setup({
      cmd = vim.lsp.rpc.connect("127.0.0.1", 9257),
      detectors = {
        with_treesitter = {
          norg = detector_for_norg,
        },
      },
    })
  end,
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
[9]: https://github.com/Saghen/blink.cmp
