# unreal.nvim

A Neovim plugin for working on Unreal Engine C++ projects: source/header switching, clangd compilation-database generation, `UFUNCTION`/`UCLASS` macro attribute completion, function implementation stubbing, and Unreal-aware treesitter/telescope integration.

> **Work in progress:** commands, config options, and behavior may change without notice.

## Features

- Switch between header and source
- Generate function implementation stubs from a header declaration
- Rebuild the clangd compilation database
- Complete `UCLASS`/`UFUNCTION`/`UPROPERTY` macro attributes
- Find/grep source files via telescope
- Open the `.uproject` with the OS default handler
- Per-project engine path, cached across sessions
- Unreal-aware treesitter grammar (via [taku25/tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp)) and telescope ignore patterns

## Requirements

- Neovim >= 0.12
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter), `main` branch (the `master` branch is not supported)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) with clangd set up (`SwitchSourceHeader` falls back to `:LspClangdSwitchSourceHeader`)
- `rg`, `clangd`, and `dotnet` on `$PATH`
- An installed Unreal Engine build to point the plugin at

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

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

After installing, run `:TSUpdate cpp` once so nvim-treesitter builds the Unreal C++ grammar.

> **Note:** the plugin replaces nvim-treesitter's `cpp` parser with [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp). This applies to every C++ file, not only Unreal projects, and there is no opt-out: `CreateImpl` and `CompleteMacro` depend on it.

Or call `setup()` explicitly:

```lua
require('unreal').setup({
    -- see Configuration below
})
```

## Configuration

`setup()` accepts the following options (all optional):

```lua
require('unreal').setup({
    -- Grammar registered as nvim-treesitter's `cpp` parser, adding Unreal-specific
    -- nodes (unreal_class_declaration, uclass_macro, ...). Used for every C++ file.
    -- Override url/revision to pin another build of the grammar.
    custom_treesitter = {
        url = 'https://github.com/taku25/tree-sitter-unreal-cpp',
        revision = '2d2d5c19a9a83e432e43c041252106995614b29a',
    },

    -- Name of the user command, e.g. "UE" gives :UE OpenProject.
    command_lead = "Unreal",

    -- Command-line abbreviations, expanded to "<command_lead> <value>".
    -- Empty by default -- add your own, e.g.:
    cmd_abbreviations = {
        uo  = "OpenProject",
        uc  = "RebuildClangd",
        uss = "SwitchSourceHeader",
        uci = "CreateImpl",
        ucm = "CompleteMacro",
        ufs = "FindSource",
        ugs = "GrepSource",
    },

    -- Lua patterns appended to telescope's global `file_ignore_patterns`, so they
    -- apply to every telescope picker, not only FindSource/GrepSource.
    -- Setting this REPLACES the defaults (Unreal binaries, assets and generated
    -- directories such as Binaries/, Intermediate/). To keep them, copy the list
    -- from `require('unreal.config').defaults.telescope_extended_ignores` and edit it.
    -- telescope_extended_ignores = { ... },

    -- Extra arguments appended to the UnrealBuildTool GenerateClangDatabase invocation.
    clangd_build_args = {
        "-NoExecCodeGenActions",
    },
})
```

## Commands

All functionality is exposed through a single command (`:Unreal` by default, see `command_lead`) with subcommand completion:

| Command | Description |
|---|---|
| `:Unreal SetEnginePath` | Prompt for and store the engine path for the current project |
| `:Unreal OpenProject` | Open the `.uproject` in the working directory with the OS default handler |
| `:Unreal RebuildClangd` | Regenerate `compile_commands.json` via `UnrealBuildTool` and copy it into the working directory |
| `:Unreal SwitchSourceHeader` | Switch between the current header and its matching source file |
| `:Unreal CreateImpl` | Generate a `.cpp` implementation stub for the function under the cursor (in a header) |
| `:Unreal CompleteMacro` | Complete a `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` attribute under the cursor |
| `:Unreal FindSource` | Find header/cpp/both files via telescope |
| `:Unreal GrepSource` | Live grep header/cpp/both files via telescope |

If multiple `.uproject` files are found in the working directory tree, commands that need one (`OpenProject`, `RebuildClangd`) will prompt you to choose.

The engine path is resolved per-project (keyed by the nearest `.uproject` directory found upward from the current working directory) and cached in `stdpath('data')/unreal.nvim/lock.dat`. A path counts as valid only if it contains `Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll`; otherwise you are prompted again.

Run `:checkhealth unreal` to check dependencies and the engine path for the current project. See `:help unreal.nvim` or the [doc](doc/) directory for the full reference.

## Acknowledgements

The custom Unreal C++ treesitter grammar is [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp) by [taku25](https://github.com/taku25).

## License

[MIT](LICENSE)
