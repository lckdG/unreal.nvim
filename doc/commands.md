# Commands

<!-- panvimdoc-include-comment
```vimdoc
                                                                     *:Unreal*
```
-->

All commands are `:Unreal <Group> <Action>` (see [command_lead](#command_lead)), with `<Tab>` completion for both words. If several `.uproject` files are found, commands that need one prompt you to choose.

## Engine

### Engine SetPath

<!-- panvimdoc-include-comment
```vimdoc
                                                      *:Unreal-Engine-SetPath*
```
-->

Prompt for the engine path of the current project and save it. See [Engine path](#engine-path).

## Project

### Project Open

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Project-Open*
```
-->

Open the `.uproject` in the working directory in the Unreal editor (on Windows, with the default handler).

## Build

### Build Clangd

<!-- panvimdoc-include-comment
```vimdoc
                                                        *:Unreal-Build-Clangd*
```
-->

Regenerate `compile_commands.json` with UnrealBuildTool and copy it into the working directory. UnrealBuildTool runs with the engine's bundled `dotnet` when there is one, otherwise with the one from `$PATH` (see [Engine path](#engine-path)). Output is shown in a terminal split; press any key to close it when the build is done.

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

Find header, source, or both kinds of files with `rg`. Asks for the file type first, then:

- built-in UI: asks for part of the file name, runs the search once and fills the quickfix list
- with an [extension](#extensions) such as Telescope: opens its live file search

### Search Grep

<!-- panvimdoc-include-comment
```vimdoc
                                                         *:Unreal-Search-Grep*
```
-->

Grep header, source, or both kinds of files with `rg`. Asks for the file type first, then:

- built-in UI: asks for the pattern, runs the search once and fills the quickfix list
- with an [extension](#extensions) such as Telescope: opens its live grep

## Deprecated names

The old one-word commands still work until 0.2.0, with a deprecation warning:

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
