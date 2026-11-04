# Introduction

<!-- panvimdoc-include-comment
```vimdoc
                                                                 *unreal.nvim*
```
-->

**unreal.nvim** helps working on Unreal Engine C++ projects: source/header switching, clangd compilation-database generation, `UFUNCTION`/`UCLASS` macro attribute completion, function implementation stubbing, an Unreal-aware treesitter grammar, and optional extensions.

> **Warning:** this plugin is a work in progress. Commands, config options, and behavior may change without notice.

## Features

- Switch between header and source
- Generate function implementation stubs from a header declaration
- Rebuild the clangd compilation database
- Complete `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` macro attributes
- Find/grep source, `.ini` and `Build.cs`/`Target.cs` files
- Open the `.uproject` in the Unreal editor
- Edit the `.uproject` in a buffer
- Per-project engine path, cached across sessions
- Optional extensions, e.g. telescope integration
- Unreal-aware treesitter grammar

## Acknowledgements

The custom Unreal C++ treesitter grammar is [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp) by [taku25](https://github.com/taku25).
