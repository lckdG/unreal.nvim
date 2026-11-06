# unreal.nvim

A Neovim plugin for working on Unreal Engine C++ projects: source/header switching, clangd compilation-database generation, `UFUNCTION`/`UCLASS` macro attribute completion, function implementation stubbing, an Unreal-aware treesitter grammar, and optional extensions.

> **Work in progress:** commands, config options, and behavior may change without notice.

## Features

- Switch between header and source
- Generate function implementation stubs from a header declaration
- Rebuild the clangd compilation database
- Complete `UCLASS`/`UFUNCTION`/`UPROPERTY` macro attributes
- Find/grep source files
- Open the `.uproject` in the Unreal editor
- Edit the `.uproject` in a buffer
- Finds installed engines and picks the one each `.uproject` asks for
- Optional extensions, e.g. telescope integration
- Unreal-aware treesitter grammar (via [taku25/tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp))

## Requirements

- Neovim >= 0.12
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter), `main` branch (the `master` branch is not supported)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- `rg` and `clangd` on `$PATH`
- clangd enabled with `vim.lsp` (see below)
- `dotnet` prioritizes the bundled executable from the engine, then the one from `$PATH`
- Optional: plugins needed by the [extensions](#extensions) you enable
- An installed Unreal Engine build to point the plugin at

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

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

Configure and enable clangd with `vim.lsp`:

```lua
vim.lsp.config("clangd", {
    cmd = { "clangd" },
    filetypes = { "c", "cpp" },
    root_markers = { "compile_commands.json", ".git" },
})
vim.lsp.enable("clangd")
```

After installing, run `:TSUpdate cpp` once so nvim-treesitter builds the Unreal C++ grammar.

> **Note:** the plugin replaces nvim-treesitter's `cpp` parser with [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp). This applies to every C++ file, not only Unreal projects, and there is no opt-out: `Code Impl` and `Code Macro` depend on it.

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

    -- Name of the user command, e.g. "UE" gives :UE Project Open.
    command_lead = "Unreal",

    -- Most .uproject files to look for under the project folder; the search stops there.
    uproject_limits = 5,

    -- Command-line abbreviations, expanded to "<command_lead> <value>".
    -- Empty by default -- add your own, e.g.:
    cmd_abbreviations = {
        uo  = "Project Open",
        uc  = "Build Clangd",
        uss = "Code SwitchSourceHeader",
        uci = "Code Impl",
        ucm = "Code Macro",
        ufs = "Search Files",
        ugs = "Search Grep",
    },

    -- Extra arguments appended to the UnrealBuildTool GenerateClangDatabase invocation.
    clangd_build_args = {
        "-NoExecCodeGenActions",
    },

    -- Optional integrations, none enabled by default. See Extensions below.
    extensions = {},
})
```

`telescope_extended_ignores` is deprecated and will be removed in 0.3.0; use `extensions.telescope.ignores` instead.

## Extensions

Extensions are optional integrations with other plugins, enabled through the `extensions` option. Available: Telescope.

### Telescope

Makes `Search Files` / `Search Grep` live telescope pickers, and opens uproject and macro choices in telescope (with macro documentation preview):

```lua
require('unreal').setup({
    extensions = {
        telescope = {
            -- Lua patterns appended to telescope's global `file_ignore_patterns`,
            -- so they apply to every telescope picker. No defaults.
            ignores = { "%.uasset", "%.umap" },
        },
    },
})
```

`telescope = true` enables it without options. Without the extension, the plugin uses `vim.ui.select` / `vim.ui.input` and fills the quickfix list for searches. Other pickers can be plugged in with `require('unreal.ui').Use(provider)`, see `:help unreal-extensions`.

## Commands

All functionality is exposed through a single command (`:Unreal` by default, see `command_lead`) as `:Unreal <Group> <Action>`, with completion for both words:

| Command | Description |
|---|---|
| `:Unreal Engine SetPath` | Prompt for an engine folder to use instead of the one the `.uproject` asks for (this session only) |
| `:Unreal Engine ClearPath` | Forget the folder from `Engine SetPath` |
| `:Unreal Project Open` | Open the project's `.uproject` in the Unreal editor |
| `:Unreal Project Edit` | Open the project's `.uproject` in a buffer |
| `:Unreal Project Select` | Choose which `.uproject` the other commands use |
| `:Unreal Build Clangd` | Regenerate `compile_commands.json` via `UnrealBuildTool` and copy it next to the `.uproject` |
| `:Unreal Code SwitchSourceHeader` | Switch between the current header and its matching source file (falls back to clangd) |
| `:Unreal Code Impl` | Generate a `.cpp` implementation stub for the function under the cursor (in a header) |
| `:Unreal Code Macro` | Complete a `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` attribute under the cursor |
| `:Unreal Search Files` | Find header/cpp, `.ini` or `Build.cs`/`Target.cs` files (quickfix list, or live with an extension) |
| `:Unreal Search Grep` | Grep header/cpp, `.ini` or `Build.cs`/`Target.cs` files (quickfix list, or live with an extension) |

`.uproject` files are searched under the project folder: the closest one above the working directory that has a `.uproject`; if there is none, the closest one with `.git` or `.p4ignore`, and finally the working directory itself. If several are found, the first command that needs one (`Project Open`, `Project Edit`, `Build Clangd`) asks you to choose, and the choice is kept until you `:cd` to another project or run `Project Select`.

The old one-word names (`OpenProject`, `RebuildClangd`, ...) still work until 0.3.0, with a deprecation warning.

The engine is found automatically: installed engines are read from the Epic launcher list (Windows, Mac), the registry (Windows source builds) or `~/.config/Epic/UnrealEngine/Install.ini` (Linux), and the one named by the `.uproject`'s `EngineAssociation` is used. If it is not found, commands ask for the engine folder. An engine folder is accepted when it has `Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll` and a usable `dotnet`. Nothing is saved to disk.

`dotnet` prioritizes the bundled executable from the engine (`Engine/Binaries/ThirdParty/DotNet/<version>/<os>-<arch>/`, newest version first), then the one from `$PATH`.

Run `:checkhealth unreal` to check dependencies, the chosen `.uproject`, its engine and the engine version. See `:help unreal.nvim` or the [doc](doc/) directory for the full reference.

## Acknowledgements

The custom Unreal C++ treesitter grammar is [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp) by [taku25](https://github.com/taku25).

## License

[MIT](LICENSE)
