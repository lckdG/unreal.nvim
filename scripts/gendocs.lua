local docgen = require("docgen")

local input_files = {
    "lua/unreal/init.lua",
    "lua/unreal/config.lua",
    "lua/unreal/functions.lua",
    "lua/unreal/health.lua",
    "lua/unreal/logs.lua",
}
table.sort(input_files)

local output_file = "doc/unreal.txt"
local output_file_handle = io.open(output_file, "w")

output_file_handle:write("*unreal.txt*  Neovim plugin for Unreal Engine C++ projects\n\n")
output_file_handle:write("==============================================================================\n")
output_file_handle:write("INTRODUCTION                                                    *unreal-intro*\n\n")
output_file_handle:write("unreal.nvim helps working on Unreal Engine C++ projects: source/header\n")
output_file_handle:write("switching, clangd compilation-database generation, UFUNCTION/UCLASS macro\n")
output_file_handle:write("attribute completion, function implementation stubbing, and Unreal-aware\n")
output_file_handle:write("treesitter/telescope integration.\n\n")
output_file_handle:write("WARNING: this plugin is a work in progress. Commands, config options, and\n")
output_file_handle:write("behavior may change without notice.\n\n")
output_file_handle:write("The custom Unreal C++ treesitter grammar is tree-sitter-unreal-cpp by\n")
output_file_handle:write("taku25: https://github.com/taku25/tree-sitter-unreal-cpp\n\n")
output_file_handle:write("==============================================================================\n")

for _, input_file in ipairs(input_files) do
    docgen.write(input_file, output_file_handle)
end

output_file_handle:write(" vim:tw=78:ts=8:ft=help:norl:\n")
output_file_handle:close()

vim.cmd("qa!")
