# Extensions

Extensions are optional integrations, enabled through the `extensions` option in [Config](#config). Nothing is enabled by default.

## Telescope

Runs pickers and searches through [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim):

- [Search Files](#search) and [Search Grep](#search) become live telescope pickers
- uproject and macro choices open in a telescope picker; [Code Macro](#code) previews the macro documentation

```lua
require('unreal').setup({
    extensions = {
        telescope = {
            ignores = { "%.uasset", "%.umap" },
        },
    },
})
```

`telescope = true` enables it with no options.

`ignores` are Lua patterns appended to telescope's global `file_ignore_patterns`, so they apply to every telescope picker, not only Search Files / Search Grep. There are no default patterns.

If telescope.nvim is not installed, an error is shown and the built-in UI is kept.

## Custom UI provider

All prompts, pickers and searches go through `require('unreal.ui')`. Without an extension it uses `vim.ui.select`, `vim.ui.input` and the quickfix list, so plugins that replace `vim.ui` (dressing.nvim, snacks.nvim) apply.

To plug in another picker, pass a provider to `Use()` after `setup()`. It must implement all four functions:

```lua
require('unreal.ui').Use({
    -- items: { name = string, value = any, desc = string[] | "" }
    -- call cb with the chosen item, or nil when cancelled
    Select = function(items, opts, cb) end,
    -- same signature as vim.ui.input
    Input = function(opts, cb) end,
    -- cmd: { "rg", "--files", <scope args...> }
    FileSearch = function(cmd, opts) end,
    -- cmd: { "rg", "--vimgrep", "-S", <scope args...> }, without the search pattern
    GrepSearch = function(cmd, opts) end,
})
```

`<scope args...>` can be several args, e.g. `--no-ignore -g !Intermediate/ -g *.ini`; the last one is always the file name glob. Use `cmd` as given; do not assume it ends with `-g <glob>` only.

`opts.prompt` holds the prompt or picker title. `desc` holds documentation lines for [Code Macro](#code) items and is `""` otherwise. `Use(nil)` restores the built-in UI.
