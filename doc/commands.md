# Commands

<!-- panvimdoc-include-comment
```vimdoc
                                                                     *:Unreal*
```
-->

All commands are subcommands of `:Unreal` (see [command_lead](#command_lead)), with `<Tab>` completion. If several `.uproject` files are found, commands that need one prompt you to choose.

## SetEnginePath

Prompt for the engine path of the current project and save it. See [Engine path](#engine-path).

## OpenProject

Open the `.uproject` in the working directory in the Unreal editor (on Windows, with the default handler).

## RebuildClangd

Regenerate `compile_commands.json` with UnrealBuildTool and copy it into the working directory. Output is shown in a terminal split; press any key to close it when the build is done.

## SwitchSourceHeader

Switch between a header and its source file. Searches the module's `Public`/`Private` folders first, then falls back to clangd.

## CreateImpl

With the cursor on a function declaration in a header, append an implementation stub to the matching `.cpp`, or jump to it if it exists.

- `BlueprintNativeEvent` and RPC functions: `_Implementation` stub
- `WithValidation`: also a `_Validate` stub
- `BlueprintImplementableEvent`: no stub
- Pure virtual, deleted and inline functions: no stub

## CompleteMacro

Complete a `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` specifier under the cursor. Requires clangd.

## FindSource

Find header, source, or both kinds of files with `rg`. Asks for the file type first, then:

- built-in UI: asks for part of the file name, runs the search once and fills the quickfix list
- with an [extension](#extensions) such as Telescope: opens its live file search

## GrepSource

Grep header, source, or both kinds of files with `rg`. Asks for the file type first, then:

- built-in UI: asks for the pattern, runs the search once and fills the quickfix list
- with an [extension](#extensions) such as Telescope: opens its live grep
