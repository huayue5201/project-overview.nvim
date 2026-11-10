# project-overview.nvim

一屏看清一个项目：身份 / 规模 / 目录结构 / 最近活跃区 / 构建入口 / 依赖 / 约定。
非 git 目录也能用（直接按目录统计）。

- `:ProjectOverview` 精简版，`:ProjectOverview!` 完整版
- 窗口内：`q` / `<Esc>` 关闭，`t` 精简⇄完整，`r` 重新采集，`gd` 跳到光标下的文件
- 采集并行异步（tokei / git log），按 repo + HEAD 缓存
- 语言行数优先 tokei，没有则回落 `git ls-files + wc -l`
- 概览 buffer 是只读 markdown（`project-overview://...`），可 yank / 搜索 / 跳转
- AI / chat 集成通过回调注入，插件本身零业务依赖

## 安装

```lua
{
  dir = "~/neovim-plugins/project-overview.nvim",
  config = function()
    require("project_overview").setup({
      keys = { open = "<leader>ii", ask = "<leader>ia", chat = "<leader>ic" },
      ask = function(digest, tokens, opts) ... end,
      chat = function(digest, tokens, opts) ... end,
    })
  end,
}
```

## 配置

```lua
require("project_overview").setup({
  keys = false, -- 或 { open=..., ask=..., chat=... }；默认不注册全局键
  commands = {
    open = "ProjectOverview",
    ask = "ProjectOverviewAsk",   -- 仅当 ask 回调存在时注册
    chat = "ProjectOverviewChat", -- 仅当 chat 回调存在时注册
  },
  buffer_scheme = "project-overview://",
  resolve_root = function(opts) return "/path/to/root" end, -- 可选
  ask = function(digest, tokens, opts) end,
  chat = function(digest, tokens, opts) end,
  digest_contract = nil, -- nil = 默认阅读契约；false = 不附加；字符串 = 自定义
  bridge_action = "project",
})
```

### ask / chat 回调

```lua
ask = function(text, tokens, opts)
  require("my_ai").ask({
    note = ("概览 ~%d tok"):format(tokens),
    extension = { digest = text },
  })
end,
```

回调抛错会被插件捕获并 `vim.notify(..., WARN)`。

## API

- `open(opts)`：`{ full?, root?, force? }`
- `digest(data, opts)`：把采集数据压成紧凑摘要，`opts.contract` 控制阅读契约
- `bridge(req)`：按 root 返回 digest（给外部 agent / RPC），`{ root?, path?, full?, wait_ms? }`
- `ask(opts)` / `chat(opts)`：走当前配置的回调
- `setup(opts)`：注册命令与键位

## 依赖

- 必需：Neovim >= 0.10、`git`（可选，没有就按目录统计）
- 可选：`tokei`（更准确的行数统计）
- 非 git 兜底统计在 macOS/Linux 上依赖 `sh` / `find` / `wc`

## 渲染器集成

概览 buffer 的名字以 `buffer_scheme` 开头，markdown 渲染器应按此前缀跳过它：

```lua
if name:match("^project%-overview://") then return true end
```

高亮组：`ProjectOverviewIcon`、`ProjectOverviewDirIcon`、`ProjectOverviewNumber`、
`ProjectOverviewKey`、`ProjectOverviewPath`、`ProjectOverviewDim`、
`ProjectOverviewOk`、`ProjectOverviewWarn`。

## 测试

```sh
./tests/run.sh
```

## License

MIT
