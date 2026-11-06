# Commands

<!-- panvimdoc-include-comment
```vimdoc
                                                                     *:Unreal*
```
-->

All commands are `:Unreal <Group> <Action>` (see [command_lead](#command_lead)), with `<Tab>` completion for both words. If several `.uproject` files are found, the first command that needs one asks you to choose, and the choice is kept for the session (see [Engine path](#engine-path)).

## Engine

### Engine SetPath

<!-- panvimdoc-include-comment
```vimdoc
                                                      *:Unreal-Engine-SetPath*
```
-->

Prompt for an engine folder and use it for every command instead of the engine the `.uproject` asks for. It is kept until `Engine ClearPath`, a `:cd` to another project, or Neovim closes; it is not saved to disk. See [Engine path](#engine-path).

### Engine ClearPath

<!-- panvimdoc-include-comment
```vimdoc
                                                    *:Unreal-Engine-ClearPath*
```
-->

Forget the folder set with `Engine SetPath`, so commands go back to the engine the `.uproject` asks for.

## Project

### Project Open

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Project-Open*
```
-->

Open the project's `.uproject` in the Unreal editor, using the engine the `.uproject` asks for. The editor runs in the background and keeps running if Neovim closes.

### Project Edit

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Project-Edit*
```
-->

Open the project's `.uproject` in a buffer. No engine needed. `.uproject` and `.uplugin` files open as `json`, indented with tabs (4 wide) like Unreal writes them.

### Project Select

<!-- panvimdoc-include-comment
```vimdoc
                                                      *:Unreal-Project-Select*
```
-->

Choose which `.uproject` the other commands use. Only needed when the project folder has several; with one, it is picked automatically.

## Build

### Build Clangd

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Build-Clangd*
```
-->

Regenerate `compile_commands.json` with UnrealBuildTool and copy it next to the `.uproject`. Only `dotnet` and UnrealBuildTool are needed, not the editor, so it also works on a source build before the editor is compiled. UnrealBuildTool runs with the engine's bundled `dotnet` when there is one, otherwise with the one from `$PATH` (see [Engine path](#engine-path)). Output is shown in a terminal split; press any key to close it when the build is done.

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
