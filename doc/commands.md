# Commands

<!-- panvimdoc-include-comment
```vimdoc
                                                                     *:Unreal*
```
-->

All commands are `:Unreal <Group> <Action>` (see [command_lead](#command_lead)), with `<Tab>` completion for both words. See [Engine path](#engine-path) for how the `.uproject` and engine are chosen.

## Engine

### Engine SetPath

<!-- panvimdoc-include-comment
```vimdoc
                                                      *:Unreal-Engine-SetPath*
```
-->

Use an engine folder you type instead of the one the `.uproject` asks for. Lasts until `Engine ClearPath`, `:cd` to another project, or Neovim closes.

### Engine ClearPath

<!-- panvimdoc-include-comment
```vimdoc
                                                    *:Unreal-Engine-ClearPath*
```
-->

Forget the `Engine SetPath` folder.

### Engine Checkout

<!-- panvimdoc-include-comment
```vimdoc
                                                     *:Unreal-Engine-Checkout*
```
-->

Pick an engine release tag (newest first) from [engine_source](#engine_source) `git_url` and clone it into `<clone_dir>/<tag>` in a terminal split. Only the tag's latest commit is downloaded (`git clone --depth 1`). Needs `git`, and access to the repository: Epic's repository is private until you link your GitHub account to your Epic Games account. Shows an error if `clone_dir` is not set or does not exist.

## Project

### Project Open

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Project-Open*
```
-->

Open the project in the Unreal editor. The editor keeps running if Neovim closes.

### Project Edit

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Project-Edit*
```
-->

Open the `.uproject` in a buffer. `.uproject` and `.uplugin` files open as `json` with 4-wide tabs.

### Project Select

<!-- panvimdoc-include-comment
```vimdoc
                                                      *:Unreal-Project-Select*
```
-->

Choose which `.uproject` the other commands use, e.g. when the project folder has several.

## Build

### Build Clangd

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Build-Clangd*
```
-->

Regenerate `compile_commands.json` with UnrealBuildTool and copy it next to the `.uproject`. Does not need the editor. Output shows in a terminal split; press any key to close it when done.

### Build Config

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Build-Config*
```
-->

Pick a `BuildConfiguration.xml` (UnrealBuildTool settings) and open it:

| Entry | File |
| --- | --- |
| Project Config | `<project>/Saved/UnrealBuildTool/BuildConfiguration.xml` |
| User Config | `~/.config/Unreal Engine/UnrealBuildTool/BuildConfiguration.xml` (Linux, Mac) |
| User AppData / Document Config | `%APPDATA%\Unreal Engine\UnrealBuildTool\…` and `Documents\Unreal Engine\UnrealBuildTool\…` (Windows) |
| Engine Config | `<engine>/Engine/Saved/UnrealBuildTool/BuildConfiguration.xml` |

Project and Engine entries need a chosen `.uproject`. A missing file is created from a template after you confirm, and written when you save.

## Code

### Code Impl

<!-- panvimdoc-include-comment
```vimdoc
                                                           *:Unreal-Code-Impl*
```
-->

With the cursor on a function declaration in a header, append an implementation stub to the matching `.cpp`, or jump to it if it exists.

- `BlueprintNativeEvent` and RPC functions: `_Implementation` stub
- `WithValidation`: also a `_Validate` stub
- `BlueprintImplementableEvent`: no stub
- Pure virtual, deleted and inline functions: no stub

### Code Macro

<!-- panvimdoc-include-comment
```vimdoc
                                                          *:Unreal-Code-Macro*
```
-->

Complete a `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` specifier under the cursor. Requires clangd.

### Code SwitchSourceHeader

<!-- panvimdoc-include-comment
```vimdoc
                                             *:Unreal-Code-SwitchSourceHeader*
```
-->

Switch between a header and its source file. Looks in the module's `Public`/`Private` folders first; if nothing matches, asks clangd.

## Search

### Search Files

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Search-Files*
```
-->

Find files with `rg`. Asks for the file type first (scopes are listed below), then:

- built-in UI: asks for part of the file name, runs the search once and fills the quickfix list
- with an [extension](#extensions) such as Telescope: opens its live file search

### Search Grep

<!-- panvimdoc-include-comment
```vimdoc
                                                         *:Unreal-Search-Grep*
```
-->

Grep files with `rg`. Asks for the file type first (scopes are listed below), then:

- built-in UI: asks for the pattern, runs the search once and fills the quickfix list
- with an [extension](#extensions) such as Telescope: opens its live grep

### Search scopes

| Scope | Files |
| --- | --- |
| All | `*.h`, `*.cpp` |
| Headers | `*.h` |
| Cpp | `*.cpp` |
| Ini | `*.ini`, including gitignored ones such as `Saved/Config/`; skips `Intermediate/`, `Binaries/` and `CrashReportClient/` |
| Build Files | `*.Build.cs`, `*.Target.cs` |

With the built-in UI, the typed name only matches the part before the extension. For Build Files that is the module or target name: `Editor` finds `GameEditor.Target.cs`, `Target` finds nothing.

## Deprecated names

The old one-word commands still work until 0.3.0, with a deprecation warning:

| Old | New |
| --- | --- |
| `SetEnginePath` | `Engine SetPath` |
| `OpenProject` | `Project Open` |
| `RebuildClangd` | `Build Clangd` |
| `CreateImpl` | `Code Impl` |
| `CompleteMacro` | `Code Macro` |
| `SwitchSourceHeader` | `Code SwitchSourceHeader` |
| `FindSource` | `Search Files` |
| `GrepSource` | `Search Grep` |
