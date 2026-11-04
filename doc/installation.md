# Installation

## Requirements

- Neovim >= 0.12
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- `rg` and `clangd` on `$PATH`
- clangd enabled with `vim.lsp` (see [clangd](#clangd))
- An installed Unreal Engine build

Use the nvim-treesitter `main` branch; `master` is not supported.

`dotnet` prioritizes the bundled executable from the engine, then the one from `$PATH`, so you usually don't need to install it. See [Engine path](#engine-path).

[Extensions](#extensions) are optional and may need other plugins.

## lazy.nvim

```lua
{
    "lckdG/unreal.nvim",
    dependencies = {
        { "nvim-treesitter/nvim-treesitter", branch = "main" },
        "nvim-lua/plenary.nvim",
    },
    opts = {},
}
```

Or call `setup()` yourself:

```lua
require('unreal').setup({})
```

## clangd

Configure and enable clangd with `vim.lsp`:

```lua
vim.lsp.config("clangd", {
    cmd = { "clangd" },
    filetypes = { "c", "cpp" },
    root_markers = { "compile_commands.json", ".git" },
})
vim.lsp.enable("clangd")
```

## Tree-sitter grammar

After installing, run `:TSUpdate cpp` once so nvim-treesitter builds the Unreal C++ grammar.

The plugin replaces nvim-treesitter's `cpp` parser with [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp). This applies to every C++ file, not only Unreal projects, and there is no opt-out: [CreateImpl](#createimpl) and [CompleteMacro](#completemacro) depend on it.
