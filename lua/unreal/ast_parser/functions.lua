local utils = require('unreal.ast_parser.utils')
local keys = require('unreal.ast_parser.keys')

local M = {}

--- Find the root declaration node, starting from a child node
---@param childNode TSNode
---@return TSNode? declarationNode
local function FindDeclaration(childNode)
    local typeDeclaration = keys.TypeDeclaration

    ---
    ---@param node? TSNode
    ---@return boolean
    local function IsDeclarationNode(node)
        return node ~= nil and vim.tbl_contains(typeDeclaration, node:type())
    end

    ---@type TSNode?
    local declarationNode = childNode
    while not IsDeclarationNode(declarationNode) do
        if declarationNode == nil then
            break
        end

        declarationNode = declarationNode:parent()
    end

    if IsDeclarationNode(declarationNode) then
        return declarationNode
    end

    return nil
end

---
---@param node TSNode
function M.GetTypeName(node)
    local declarationNode = FindDeclaration(node)

    if declarationNode == nil then
        return ""
    end

    for childNode, _ in declarationNode:iter_children() do
        if childNode:type() == keys.TypeIdentifier then
            return vim.treesitter.get_node_text(childNode, 0)
        end
    end

    return ""
end

---
---@param queryInfo QueryInfo
---@param className string
---@return table
function M.GetDeclarationTemplate(queryInfo, className)
    local result = {}

    if not utils.IsQueryInfoValid(queryInfo) then
        return result
    end

    local bufnr = queryInfo.bufnr
    local cursorRow = queryInfo.cursorRow
    local lang = queryInfo.lang
    local root = queryInfo.root

    local query = vim.treesitter.query.parse(lang, [[
        (_
            [
                (type_identifier)
                (primitive_type)
            ]? @function.type

            (function_declarator
                [
                    (identifier)
                    (field_identifier)
                ] @function.name
                (parameter_list
                    (parameter_declaration
                        (_
                            ((identifier) @function.params.identifier)
                        )
                    )
                ) @function.params
                (type_qualifier)? @function.const
            )
        )
    ]])

    local paramIdentifiers = {}

    for id, capturedNode, _ in query:iter_captures(root, bufnr, cursorRow, cursorRow + 1) do
        local queryId = query.captures[id]
        local text = vim.treesitter.get_node_text(capturedNode, bufnr)

        if queryId == "function.params.identifier" then
            table.insert(paramIdentifiers, text)
        elseif queryId == "function.name" then
            result[queryId] = className .. "::" .. text
        else
            result[queryId] = text
        end
    end

    result.paramIdentifiers = paramIdentifiers
    return result
end

---
---@param queryInfo QueryInfo
---@return TSNode? macroNode
---@return string macroIdentifier
---@return table existedVariables
function M.GetMacro(queryInfo)
    local existedVariables = {}

    if not utils.IsQueryInfoValid(queryInfo) then
        return nil, "", existedVariables
    end

    local bufnr = queryInfo.bufnr
    local cursorRow = queryInfo.cursorRow
    local lang = queryInfo.lang
    local root = queryInfo.root

    local query = vim.treesitter.query.parse(lang, [[
        (_
            (unreal_specifier_list
                (unreal_specifier
                    ((unreal_specifier_keyword)? @macro.argument.identifier)
                )
           ?)
        ) @macro.declaration
        (#any-of? @macro.declaration "uclass_macro" "ustruct_macro" "ufunction_macro" "uproperty_macro")
    ]])

    local macroNode = nil
    local identifier = ""

    for id, capturedNode, _ in query:iter_captures(root, bufnr, cursorRow, cursorRow + 1) do
        if query.captures[id] == "macro.declaration" then
            macroNode = capturedNode

            local text = vim.treesitter.get_node_text(capturedNode, bufnr)
            local index, _ = string.find(text, "%(")
            if index then
                identifier = string.sub(text, 1, index - 1)
            else
                identifier = text
            end
        else
            local text = vim.treesitter.get_node_text(capturedNode, bufnr)
            table.insert(existedVariables, text)
        end
    end

    return macroNode, identifier, existedVariables
end

return M
