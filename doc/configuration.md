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
    clangd_build_args = { "-NoExecCodeGenActions" },
    extensions = {},
})
```

## custom_treesitter

Grammar registered as nvim-treesitter's `cpp` parser. Override `url` and `revision` to pin another build of the grammar.

## command_lead

Name of the user command. With `command_lead = "UE"` the commands become `:UE Project Open`, `:UE Build Clangd`, ...

## cmd_abbreviations

Command-line abbreviations, expanded to `<command_lead> <value>`:

```lua
cmd_abbreviations = { uo = "Project Open", uc = "Build Clangd" }
```

## clangd_build_args

Extra arguments for the UnrealBuildTool `-mode=GenerateClangDatabase` call made by [Build Clangd](#build). Each entry is one argument.

## extensions

Optional integrations, keyed by name. A table enables the extension with those options, `true` enables it with none, `false` disables it. Unknown names show an error. See [Extensions](#extensions).

```lua
extensions = {
    telescope = { ignores = { "%.uasset" } },
}
```

## telescope_extended_ignores

Deprecated, removed in 0.2.0. Use `extensions = { telescope = { ignores = ... } }` instead.

Still accepted for now: it shows a deprecation warning and becomes `extensions.telescope.ignores`, which enables the extension. It is ignored if `ignores` is already set there, or if the extension is set to `false`.
