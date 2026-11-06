# Health

Run `:checkhealth unreal` to check:

- `rg` and `clangd` are installed
- plenary.nvim is installed
- telescope.nvim is available, only when the [telescope extension](#telescope) is enabled
- clangd is enabled with `vim.lsp.enable("clangd")`
- `setup()` was called
- the chosen `.uproject`
- its engine (a `SetPath` folder shows as a warning) and the engine version
- the engine's editor, `dotnet` (bundled or `$PATH`) and UnrealBuildTool
