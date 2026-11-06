# Changelog

All notable changes to unreal.nvim are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Breaking

- **The engine path is no longer saved.** `stdpath('data')/unreal.nvim/lock.dat` is not read or written anymore; you can delete it. Installed engines are found automatically, and each `.uproject`'s `EngineAssociation` picks the engine.
- **`:Unreal Engine SetPath` only lasts for the session.** It overrides the engine for every command until `:Unreal Engine ClearPath`, a `:cd` to another project, or Neovim closes.

### Added

- `:Unreal Engine ClearPath` forgets the folder set with `Engine SetPath`.
- `:Unreal Project Select` chooses which `.uproject` the other commands use. The choice is kept for the session.
- A `.uproject` directly in the project folder is chosen when Neovim starts and after a `:cd` to another project, so most commands no longer ask.
- `:checkhealth unreal` shows the chosen `.uproject`, the engine it uses and the engine's version.
- `uproject_limits` option: most `.uproject` files to look for under the project folder (default 5).
- `:Unreal Build Config` opens a project, user or engine `BuildConfiguration.xml` (UnrealBuildTool settings), creating a missing one from a template after a confirm.

### Changed

- `:Unreal Project Open` starts `UnrealEditor.exe` directly on Windows instead of the `.uproject`'s default program.
- `:Unreal Build Clangd` no longer needs the editor program, only `dotnet` and UnrealBuildTool.

### Fixed

- `:Unreal Build Clangd` copies `compile_commands.json` next to the `.uproject`, not to the working directory. Opening Neovim above the project (e.g. repo root with `Game/Game.uproject`) no longer leaves the file where clangd can't pair it with the project.

## [0.2.0] - 2026-11-04

### Breaking

- **Commands are now two words: `:Unreal <Group> <Action>`.**

  | Old | New |
  | --- | --- |
  | `SetEnginePath` | `Engine SetPath` |
  | `OpenProject` | `Project Open` |
  | `RebuildClangd` | `Build Clangd` |
  | `SwitchSourceHeader` | `Code SwitchSourceHeader` |
  | `CreateImpl` | `Code Impl` |
  | `CompleteMacro` | `Code Macro` |
  | `FindSource` | `Search Files` |
  | `GrepSource` | `Search Grep` |

  `cmd_abbreviations` values must use the new names, e.g. `uc = "Build Clangd"`.
- **telescope.nvim is optional.** It is now an extension you turn on with `extensions = { telescope = true }` (or a table of options). Without it, the built-in UI is used: `vim.ui.select` / `vim.ui.input`, and search results go to the quickfix list.
- **No default telescope ignore patterns.** The built-in list of ignored files (`.uasset`, `.dll`, `Binaries/`, `Intermediate/`, ...) is gone; set your own with `extensions = { telescope = { ignores = { ... } } }`.
- **nvim-lspconfig is no longer required.** clangd only needs to be on `$PATH` and enabled with `vim.lsp.enable("clangd")`. Existing lspconfig setups keep working.
- **Engine path rules changed.** An engine path is accepted when it has `UnrealBuildTool.dll` and a usable `dotnet`. A saved path without either is rejected and you are asked again.

### Deprecated

These still work, with a deprecation warning, and will be removed in 0.3.0:

- The old one-word command names (`RebuildClangd`, `OpenProject`, ...).
- `telescope_extended_ignores`. It becomes `extensions.telescope.ignores` and turns the extension on, unless `ignores` is already set there or the extension is set to `false`.

### Added

- Tab completion for both words of a command, filtered by what you have typed. Old names are not offered.
- A help tag for each command, e.g. `:h :Unreal-Build-Clangd`.
- `extensions` option for optional integrations; unknown extension names show an error.
- Custom UI providers: `require("unreal.ui").Use(provider)` replaces the select, input, file search and grep UI; `Use(nil)` restores the built-in one.
- Telescope extension: live file search and grep, uproject and macro choices in a telescope picker, macro documentation in the preview.
- `dotnet` prioritizes the bundled executable from the engine (`Engine/Binaries/ThirdParty/DotNet/<version>/<os>-<arch>/`, newest version first), then the one from `$PATH`. `Build Clangd` runs UnrealBuildTool with it.
- `:checkhealth unreal`:
  - shows the path of each item it finds (engine, editor, `dotnet`, UnrealBuildTool)
  - says whether `dotnet` is the engine's bundled one or the one from `$PATH`
  - warns when clangd is not enabled in `vim.lsp`
  - checks telescope.nvim only when the telescope extension is on
- The project folder (used to remember the engine path) falls back to the nearest `.git` / `.p4ignore` folder when there is no `.uproject`, then to the working directory.

### Changed

- `Project Open` fully detaches the Unreal Editor from Neovim: `systemd-run` (or `setsid`) on Linux, `open -n` on Mac. Closing Neovim no longer closes the editor.
- `Code SwitchSourceHeader` asks clangd directly (`textDocument/switchSourceHeader`) when no `Public`/`Private` match is found, instead of running `:LspClangdSwitchSourceHeader`.
- Pickers and prompts have titles ("Multiple uproject found, choose one", "Complete macro: ").
- An unknown group or action shows an error instead of failing silently.
- `dotnet` is no longer listed under system dependencies in checkhealth; it is checked together with the engine path.

### Fixed

- `Search Grep` treats a pattern starting with `-` as a pattern, not as an `rg` option.
- `:checkhealth unreal` no longer crashes when `setup()` was not called.
- `vim.ui.select` / `vim.ui.input` overridden by another plugin after unreal.nvim loads (e.g. dressing.nvim) are now used.
- Options passed to `setup()` no longer modify the defaults, so calling `setup()` again starts from clean defaults.
- The bundled `dotnet` is found on Linux ARM (`linux-arm64`).

## [0.1.0] - 2026-11-02

First release.

- `:Unreal` command with `SetEnginePath`, `OpenProject`, `RebuildClangd`, `SwitchSourceHeader`, `CreateImpl`, `CompleteMacro`, `FindSource` and `GrepSource`
- Per-project engine path, saved across sessions
- Unreal-aware tree-sitter grammar ([tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp))
- `command_lead`, `cmd_abbreviations`, `clangd_build_args`, `custom_treesitter` and `telescope_extended_ignores` options
- `:checkhealth unreal`
- Requires Neovim 0.12, nvim-treesitter (`main`), telescope.nvim, plenary.nvim, nvim-lspconfig, and `rg`, `clangd`, `dotnet` on `$PATH`

[0.2.0]: https://github.com/lckdG/unreal.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lckdG/unreal.nvim/releases/tag/v0.1.0
