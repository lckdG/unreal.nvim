# Health

Run `:checkhealth unreal` to check:

- `rg` and `clangd` are installed
- plenary.nvim is installed
- telescope.nvim is available, only when the [telescope extension](#telescope) is enabled
- clangd is enabled with `vim.lsp.enable("clangd")`
- `setup()` was called
- the engine path, editor, `dotnet` and UnrealBuildTool are found, with the path of each; for `dotnet` it also tells whether it is the engine's bundled one or the one from `$PATH`
