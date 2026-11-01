-- Absolute paths: tests :cd into temp projects, a relative "." would stop resolving
local root = vim.fn.getcwd()
vim.opt.runtimepath:append(root)
vim.opt.runtimepath:append(root .. "/.deps/tree-sitter-lua")
vim.opt.runtimepath:append(root .. "/.deps/plenary.nvim")
vim.opt.runtimepath:prepend(root .. "/.deps/tree-sitter-unreal-cpp") -- cpp parser used by tests
vim.cmd.runtime("plugin/plenary.vim")
