# Installation

## Requirements

- Neovim >= 0.12
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
- `rg`, `clangd` and `dotnet` on `$PATH`
- An installed Unreal Engine build

Use the nvim-treesitter `main` branch; `master` is not supported. nvim-lspconfig needs clangd set up: it provides `:LspClangdSwitchSourceHeader`, the fallback of [SwitchSourceHeader](#switchsourceheader).

## lazy.nvim

```lua
{
    "lckdG/unreal.nvim",
    dependencies = {
        { "nvim-treesitter/nvim-treesitter", branch = "main" },
        "nvim-telescope/telescope.nvim",
        "nvim-lua/plenary.nvim",
        "neovim/nvim-lspconfig",
    },
    opts = {},
}
```

Or call `setup()` yourself:

```lua
require('unreal').setup({})
```

## Tree-sitter grammar

After installing, run `:TSUpdate cpp` once so nvim-treesitter builds the Unreal C++ grammar.

The plugin replaces nvim-treesitter's `cpp` parser with [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp). This applies to every C++ file, not only Unreal projects, and there is no opt-out: [CreateImpl](#createimpl) and [CompleteMacro](#completemacro) depend on it.
