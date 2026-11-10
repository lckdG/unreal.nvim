# Health

Run `:checkhealth unreal` to check:

- `rg` and `clangd` are installed
- plenary.nvim is installed
- telescope.nvim is available, only when the [telescope extension](#telescope) is enabled
- clangd is enabled with `vim.lsp.enable("clangd")`
- `setup()` was called
- the chosen `.uproject`
- its engine, found in the same order as the commands use (a `SetPath` folder shows as a warning), and the engine version
- the engine type:
  - `launcher-installed`: listed by the Epic Games Launcher
  - `source build, native engine`: the project sits inside the engine, in a folder listed by its `.uprojectdirs` files
  - `source build, cloned into configured clone dir`: a checkout directly inside [engine_source](#engine_source) `clone_dir`
  - `source build`: any other source build registered on this machine (`Install.ini` on Linux, the registry on Windows)
  - `unknown`: a `SetPath` folder none of the above knows about (shown as info)
- the engine's editor and its `RunUBT` script (UnrealBuildTool); for a launcher engine, the advice is to verify it in the launcher
- for source builds, the `Setup`, `GenerateProjectFiles` and `Build` scripts that `Engine Build` runs
- [engine_source](#engine_source) `clone_dir` exists (only shown as info when not set) and `git` is installed, for `Engine Checkout` and `Engine Build`

Each problem comes with advice on how to fix it.
