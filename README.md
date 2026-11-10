# project-overview.nvim

Understand a project at a glance: identity / size / directory layout / hot spots / build entry points / dependencies / conventions.
Works outside git too (falls back to plain directory stats).

- `:ProjectOverview` compact view, `:ProjectOverview!` full view
- In the window: `q` / `<Esc>` close, `t` toggle compact⇄full, `r` refresh, `gd` jump to the file under the cursor
- Collection runs async in parallel (tokei / git log), cached per repo + HEAD
- Line counts prefer tokei, falling back to `git ls-files + wc -l`
- The overview buffer is read-only markdown (`project-overview://...`), so you can yank / search / jump
- AI / chat integration is done by injecting callbacks; the plugin has no business dependencies of its own

## Installation

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

## Configuration

```lua
require("project_overview").setup({
  keys = false, -- or { open=..., ask=..., chat=... }; no global keys are registered by default
  commands = {
    open = "ProjectOverview",
    ask = "ProjectOverviewAsk",   -- only registered when the ask callback exists
    chat = "ProjectOverviewChat", -- only registered when the chat callback exists
  },
  buffer_scheme = "project-overview://",
  resolve_root = function(opts) return "/path/to/root" end, -- optional
  ask = function(digest, tokens, opts) end,
  chat = function(digest, tokens, opts) end,
  digest_contract = nil, -- nil = default reading contract; false = none; string = custom
  bridge_action = "project",
})
```

### ask / chat callbacks

```lua
ask = function(text, tokens, opts)
  require("my_ai").ask({
    note = ("overview ~%d tok"):format(tokens),
    extension = { digest = text },
  })
end,
```

Errors thrown by a callback are caught by the plugin and reported with `vim.notify(..., WARN)`.

## API

- `open(opts)`: `{ full?, root?, force? }`
- `digest(data, opts)`: compress collected data into a compact digest; `opts.contract` controls the reading contract
- `bridge(req)`: returns a digest for a root (for external agents / RPC), `{ root?, path?, full?, wait_ms? }`
- `ask(opts)` / `chat(opts)`: invoke the currently configured callbacks
- `setup(opts)`: register commands and keymaps

## Requirements

- Required: Neovim >= 0.10, `git` (optional; without it, plain directory stats are used)
- Optional: `tokei` (more accurate line counts)
- The non-git fallback relies on `sh` / `find` / `wc` on macOS/Linux

## Renderer integration

The overview buffer name starts with `buffer_scheme`; markdown renderers should skip it by that prefix:

```lua
if name:match("^project%-overview://") then return true end
```

Highlight groups: `ProjectOverviewIcon`, `ProjectOverviewDirIcon`, `ProjectOverviewNumber`,
`ProjectOverviewKey`, `ProjectOverviewPath`, `ProjectOverviewDim`,
`ProjectOverviewOk`, `ProjectOverviewWarn`.

## Tests

```sh
./tests/run.sh
```

## License

MIT
