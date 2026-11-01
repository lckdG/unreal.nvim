local M = {}

M.Keys = {
    DeclType = "function.type",
    DeclName = "function.name",
    DeclParamIdentifier = "function.params.identifier",
    MacroDeclaration = "macro.declaration",
    MacroIdentifier = "macro.argument.identifier",
    MacroMetaIdentifier = "macro.meta.identifier",
    MacroSpecifierList = "unreal_specifier_list",
    TypeIdentifier = "type_identifier",
    TypeDeclaration = {
        "unreal_class_declaration",
        "unreal_interface_declaration",
        "unreal_struct_declaration",
    },
    DeclKeys = {
        "function.type",
        "function.name",
        "function.params",
        "function.const",
    }
}

--#region

---
---@param bufnr number
---@param lang string
---@return TSNode? root
local function getTreeRoot(bufnr, lang)
    local parser = vim.treesitter.get_parser(bufnr, lang)
    if parser == nil then
        return nil
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    return root
end

local function findDeclaration(childNode)
    local typeDeclaration = M.Keys.TypeDeclaration

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

--#endregion

---@param opts ConfigOpts
function M.init(opts)
    local custom_treesitter_opts = opts.custom_treesitter
    M.Hijack(custom_treesitter_opts)
end

---@param custom_treesitter_opts CustomTreesitterOpts?
function M.Hijack(custom_treesitter_opts)
    if custom_treesitter_opts == nil then return end

    vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = function ()
            require('nvim-treesitter.parsers').cpp = {
                install_info = {
                    url = custom_treesitter_opts.url,
                    revision = custom_treesitter_opts.revision,
                },
                tier = 2
            }
        end
    })
end

---
---@return boolean
---@return QueryInfo
function M.PrepareForQuery()
    local bufnr = vim.api.nvim_get_current_buf()

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then return false, {} end

    local treeRoot = getTreeRoot(bufnr, lang)
    if treeRoot == nil then
        return false, {}
    end

    local cursorPos = vim.api.nvim_win_get_cursor(0)
    local cursorRow = cursorPos[1] - 1

    local queryInfo = {
        bufnr = bufnr,
        cursorRow = cursorRow,
        lang = lang,
        root = treeRoot
    }

    return true, queryInfo
end

---
---@param node TSNode
function M.GetTypeName(node)
    local declarationNode = findDeclaration(node)

    if declarationNode == nil then
        return ""
    end

    for childNode, _ in declarationNode:iter_children() do
        if childNode:type() == M.Keys.TypeIdentifier then
            return vim.treesitter.get_node_text(childNode, 0)
        end
    end

    return ""
end

---
---@param className string
---@return table
function M.GetDeclarationTemplate(className)
    local result = {}

    local success, queryInfo = M.PrepareForQuery()
    if not success then
        return result
    end

    local bufnr = queryInfo.bufnr
    local cursorRow = queryInfo.cursorRow
    local lang = queryInfo.lang
    local root = queryInfo.root

    local query = vim.treesitter.query.get(lang, "unreal_function_declaration")
    if query == nil then
        return result
    end

    local paramIdentifiers = {}

    for id, capturedNode, _ in query:iter_captures(root, bufnr, cursorRow, cursorRow + 1) do
        local queryId = query.captures[id]
        local text = vim.treesitter.get_node_text(capturedNode, bufnr)

        if queryId == M.Keys.DeclParamIdentifier then
            table.insert(paramIdentifiers, text)
        elseif queryId == M.Keys.DeclName then
            result[queryId] = className .. "::" .. text
        else
            result[queryId] = text
        end
    end

    result.paramIdentifiers = paramIdentifiers
    return result
end

---
---@return TSNode? macroNode
---@return string macroIdentifier
---@return ExistedMacroVaiables existedVariables
function M.GetMacro()
    local existedVariables = {
        arguments = {},
        metas = {}
    }

    local success, queryInfo = M.PrepareForQuery()
    if not success then
        return nil, "", existedVariables
    end

    local bufnr = queryInfo.bufnr
    local cursorRow = queryInfo.cursorRow
    local lang = queryInfo.lang
    local root = queryInfo.root

    local query = vim.treesitter.query.get(lang, "unreal_macro")
    if query == nil then
        return nil, "", existedVariables
    end

    local macroNode = nil
    local identifier = ""

    for id, capturedNode, _ in query:iter_captures(root, bufnr, cursorRow, cursorRow + 1) do
        if query.captures[id] == M.Keys.MacroDeclaration then
            macroNode = capturedNode

            local text = vim.treesitter.get_node_text(capturedNode, bufnr)
            local index, _ = string.find(text, "%(")
            if index then
                identifier = string.sub(text, 1, index - 1)
            else
                identifier = text
            end
        elseif query.captures[id] == M.Keys.MacroIdentifier then
            local text = vim.treesitter.get_node_text(capturedNode, bufnr)
            if text ~= "meta" then
                table.insert(existedVariables.arguments, text)
            end
        else
            local text = vim.treesitter.get_node_text(capturedNode, bufnr)
            table.insert(existedVariables.metas, text)
        end
    end

    return macroNode, identifier, existedVariables
end

---Get the position for the next macro variable
---New variable is always appended to the end of the list
---If there is meta=(...) the function will always return the position before it
---The append rule applies for meta-specific values
---@param macroNode TSNode
---@param isMeta boolean
---@return MacroAddType addType
---@return number row
---@return number col
function M.GetNextMacroPosition(macroNode, isMeta)
    local types = require('unreal.types')
    local _, _, endRow, endCol = macroNode:range()

    local argumentList = macroNode:child(1)
    if argumentList == nil then
        return types.MACRO_ADD_TYPE.First, endRow, endCol - 1
    end

    local specifierList = argumentList:child(1)
    if specifierList == nil or specifierList:type() ~= M.Keys.MacroSpecifierList then
        return types.MACRO_ADD_TYPE.First, endRow, endCol - 1
    end

    local metaNode = nil
    for node, _ in specifierList:iter_children() do
        if node:child_count() > 1 then
            local childNode = node:child(0)
            if childNode ~= nil then
                local macroName = vim.treesitter.get_node_text(childNode, 0)
                if macroName == "meta" then
                    metaNode = node
                    break
                end
            end
        end
    end

    if metaNode ~= nil then
        local _, metaStartCol, metaEndRow, metaEndCol = metaNode:range()
        if isMeta == false then
            return types.MACRO_ADD_TYPE.Prepend, metaEndRow, metaStartCol
        else
            return types.MACRO_ADD_TYPE.AppendMeta, metaEndRow, metaEndCol - 1
        end
    else
        -- NOTE: if the flow goes here, there's always at least one sibling
        -- Because unreal_specifier_list is only present if #list > 0
        return types.MACRO_ADD_TYPE.Append, endRow, endCol - 1
    end
end

return M
