# Health

Run `:checkhealth unreal` to check:

- `rg` and `clangd` are installed
- plenary.nvim is installed
- telescope.nvim is available, only when the [telescope extension](#telescope) is enabled
- clangd is enabled with `vim.lsp.enable("clangd")`
- `setup()` was called
- a `.uproject` is chosen for this session (run any project command, or `:Unreal Project Select`)
- the engine for it is found: the folder from `Engine SetPath` (shown as a warning, since it overrides the `.uproject`), or the installed engine named by its `EngineAssociation`
- the engine's editor, `dotnet` and UnrealBuildTool are found, with the path of each; for `dotnet` it also tells whether it is the engine's bundled one or the one from `$PATH`
