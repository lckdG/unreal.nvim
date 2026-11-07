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
- [engine_source](#engine_source) `clone_dir` exists (only shown as info when not set) and `git` is installed, for `Engine Checkout` and `Engine Build`

Each problem comes with advice on how to fix it.
