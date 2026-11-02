# Config

All options are optional. Defaults:

```lua
require('unreal').setup({
    custom_treesitter = {
        url = 'https://github.com/taku25/tree-sitter-unreal-cpp',
        revision = '2d2d5c19a9a83e432e43c041252106995614b29a',
    },
    command_lead = "Unreal",
    cmd_abbreviations = {},
    telescope_extended_ignores = { --[[ Unreal defaults, see below ]] },
    clangd_build_args = { "-NoExecCodeGenActions" },
})
```

## custom_treesitter

Grammar registered as nvim-treesitter's `cpp` parser. Override `url` and `revision` to pin another build of the grammar.

## command_lead

Name of the user command. With `command_lead = "UE"` the commands become `:UE OpenProject`, `:UE RebuildClangd`, ...

## cmd_abbreviations

Command-line abbreviations, expanded to `<command_lead> <value>`:

```lua
cmd_abbreviations = { uo = "OpenProject", uc = "RebuildClangd" }
```

## telescope_extended_ignores

Lua patterns appended to telescope's global `file_ignore_patterns`, so they apply to every telescope picker, not only [FindSource](#findsource) / [GrepSource](#grepsource).

Setting this **replaces** the defaults (Unreal binaries, assets and generated directories such as `Binaries/` and `Intermediate/`). To keep them, copy the list from `require('unreal.config').defaults.telescope_extended_ignores` and edit it.

## clangd_build_args

Extra arguments for the UnrealBuildTool `-mode=GenerateClangDatabase` call made by [RebuildClangd](#rebuildclangd). Each entry is one argument.
