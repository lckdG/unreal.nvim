local functions = require('unreal.ast_parser.functions')

local M = {}

M.QueryInfo = {}

function M.PrepareForQuery()
    M.QueryInfo = {}

    local bufnr = vim.api.nvim_get_current_buf()

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then return false end

    local utils = require('unreal.ast_parser.utils')
    local treeRoot = utils.GetTreeRoot(bufnr, lang)
    if treeRoot == nil then
        return false
    end

    local cursorRow = utils.GetCursorRow()

    M.QueryInfo = {
        bufnr =bufnr,
        cursorRow = cursorRow,
        lang = lang,
        root = treeRoot
    }

    return true
end

---
---@param node TSNode
---@return string
function M.GetRootIdentifier(node)
    return functions.GetTypeName(node)
end

---
---@param className string
---@return table
function M.GetDeclarationTemplate(className)
    return functions.GetDeclarationTemplate(M.QueryInfo, className)
end

function M.GetDeclTypeKey()
    return require('unreal.ast_parser.keys').DeclTypeKey
end

function M.GetDeclKeys()
    return require('unreal.ast_parser.keys').DeclKeys
end

---
function M.GetMacro()
    return functions.GetMacro(M.QueryInfo)
end

return M
