# Introduction

<!-- panvimdoc-include-comment
```vimdoc
                                                                 *unreal.nvim*
```
-->

**unreal.nvim** helps working on Unreal Engine C++ projects: source/header switching, clangd compilation-database generation, `UFUNCTION`/`UCLASS` macro attribute completion, function implementation stubbing, and Unreal-aware treesitter/telescope integration.

> **Warning:** this plugin is a work in progress. Commands, config options, and behavior may change without notice.

## Features

- Switch between header and source
- Generate function implementation stubs from a header declaration
- Rebuild the clangd compilation database
- Complete `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` macro attributes
- Find/grep source files via telescope
- Open the `.uproject` in the Unreal editor
- Per-project engine path, cached across sessions
- Unreal-aware treesitter grammar and telescope ignore patterns

## Acknowledgements

The custom Unreal C++ treesitter grammar is [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp) by [taku25](https://github.com/taku25).
