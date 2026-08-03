# unreal.nvim

A Neovim plugin for working on Unreal Engine C++ projects: source/header switching, clangd compilation-database generation, `UFUNCTION`/`UCLASS` macro attribute completion, function implementation stubbing, and Unreal-aware treesitter/telescope integration.

## Features

- Switch between a header and its matching `.cpp`/`.h` source file (falls back to clangd's `SwitchSourceHeader` if no match is found)
- Generate the `.cpp` implementation stub for a function declared in a header, placed under the matching class
- Rebuild the clangd compilation database (`compile_commands.json`) via `UnrealBuildTool -mode=GenerateClangDatabase`
- Complete `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` macro attributes (e.g. `BlueprintCallable`, `EditAnywhere`) through clangd, picked with telescope
- Find/grep source files restricted to headers, cpp, or both, through telescope
- Open the `.uproject` in the working directory with the OS default handler
- Per-project engine path, resolved from the nearest `.uproject` upward from cwd and cached across sessions
- Extends telescope's `file_ignore_patterns` with Unreal-generated directories/files (`Binaries/`, `Intermediate/`, `*.uasset`, ...)
- Registers a custom treesitter grammar for Unreal C++ (`UCLASS`, `UPROPERTY`, etc. as real nodes)

## Requirements

- Neovim >= 0.10
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `rg`, `clangd`, and `dotnet` on `$PATH`
- An installed Unreal Engine build to point the plugin at

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "your-username/unreal.nvim", -- replace with the actual repo path
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
        "nvim-telescope/telescope.nvim",
    },
    opts = {},
}
```

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
    -- Grammar used to register a custom `cpp` parser with nvim-treesitter,
    -- adding Unreal-specific nodes (unreal_class_declaration, uclass_macro, ...).
    -- Set to nil to skip registering a custom grammar.
    custom_treesitter = {
        url = 'https://github.com/taku25/tree-sitter-unreal-cpp',
        revision = '2d2d5c19a9a83e432e43c041252106995614b29a',
    },

    -- Command-line abbreviations, expanded to "Unreal <value>".
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

    -- Extra file_ignore_patterns merged into telescope's config,
    -- on top of Unreal-generated directories/files already excluded by default.
    telescope_extended_ignores = {},

    -- Extra arguments appended to the UnrealBuildTool GenerateClangDatabase invocation.
    clangd_build_args = {
        "-NoExecCodeGenActions",
    },
})
```

## Commands

All functionality is exposed through a single command with subcommand completion:

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

The engine path is resolved per-project (keyed by the nearest `.uproject` directory found upward from the current working directory) and cached in `stdpath('data')/unreal.nvim/lock.dat`.

## License

[MIT](LICENSE)
