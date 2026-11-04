local M = {}

---@type table<string, string>
M.Keys = {
    DeclTemplate = "function.template",
    DeclType = "function.type",
    DeclName = "function.name",
    DeclParams = "function.params",
    MacroDeclaration = "macro.declaration",
    MacroIdentifier = "macro.argument.identifier",
    MacroMetaIdentifier = "macro.meta.identifier",
    MacroSpecifierList = "unreal_specifier_list",
    TypeIdentifier = "type_identifier",
    TypeQualifier = "type_qualifier",
    TemplateDecl = "template_declaration",
    ParamList = "parameter_list",
    Skip = "function.skip",
    OptionalParam = "optional_parameter_declaration",
    UfunctionSpecifier = "function.specifier",
}

M.DeclKeys = {
    "function.type",
    "function.name",
    "function.params",
    "function.const",
    "function.noexcept",
}

M.NonSpaceKeys = {
    "function.params",
}

---@param opts ConfigOpts
function M.init(opts)
    local custom_treesitter_opts = opts.custom_treesitter
    M.Hijack(custom_treesitter_opts)
end

---Make nvim-treesitter install an Unreal-aware C++ grammar instead of the stock one,
---so macros such as `UCLASS()` and `UPROPERTY()` parse correctly.
---Takes effect the next time nvim-treesitter installs or updates parsers (`TSUpdate`).
---`nil` keeps the stock grammar.
---@param custom_treesitter_opts CustomTreesitterOpts? `{ url, revision }` of the grammar repo
function M.Hijack(custom_treesitter_opts)
    if custom_treesitter_opts == nil then
        return
    end

    local augroup = vim.api.nvim_create_augroup("unreal.nvim.treesitter", { clear = true })
    vim.api.nvim_create_autocmd("User", {
        group = augroup,
        pattern = "TSUpdate",
        callback = function()
            require("nvim-treesitter.parsers").cpp = {
                install_info = {
                    url = custom_treesitter_opts.url,
                    revision = custom_treesitter_opts.revision,
                },
                tier = 2,
            }
        end,
    })
end

---Resolve the treesitter language of the current buffer.
---@return boolean ok false when the filetype has no treesitter language
---@return QueryInfo info `{ bufnr, lang }`, empty when not ok
function M.PrepareForQuery()
    local bufnr = vim.api.nvim_get_current_buf()

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then
        return false, {}
    end

    local queryInfo = {
        bufnr = bufnr,
        lang = lang,
    }

    return true, queryInfo
end

---Qualified name of the classes/structs enclosing `node`, outermost first, e.g. `AOuter::FInner`.
---Only definitions with a body count; returns "" outside any class.
---@param node TSNode
---@return string
function M.GetTypeName(node)
    local classRoots = {
        "unreal_class_declaration",
        "unreal_interface_declaration",
        "unreal_struct_declaration",
        "class_specifier",
        "struct_specifier",
    }

    local names = {}
    while node do
        if vim.tbl_contains(classRoots, node:type()) and node:field("body")[1] then
            local name = node:field("name")[1]
            if name then
                table.insert(names, 1, vim.treesitter.get_node_text(name, 0))
            end
        end

        node = node:parent()
    end

    return table.concat(names, "::")
end

local function getDeclarationRoot()
    local declRoots = {
        "field_declaration",
        "unreal_function_declaration",
        "declaration",
        "template_declaration",
        "function_definition",
    }

    local node = vim.treesitter.get_node()
    while node and not vim.tbl_contains(declRoots, node:type()) do
        node = node:parent()
    end

    if node == nil then
        return nil
    end
    if node:parent() and node:parent():type() == M.Keys.TemplateDecl then
        node = node:parent()
    end

    return node
end

---Return type text of the function declaration that owns `decl`.
---@param decl TSNode
---@param bufnr number
---@return string? returnType nil for constructors/destructors
local function getReturnType(decl, bufnr)
    local declTypes = {
        "field_declaration",
        "unreal_function_declaration",
        "declaration",
    }

    local fnDecl = decl:parent()
    while fnDecl and not vim.tbl_contains(declTypes, fnDecl:type()) do
        fnDecl = fnDecl:parent()
    end

    if fnDecl == nil then
        return nil
    end

    local start = fnDecl:field("type")[1]
    if start == nil then
        return nil
    end

    for child in fnDecl:iter_children() do
        if child:equal(start) then
            break
        end
        if child:type() == M.Keys.TypeQualifier then
            start = child
            break
        end
    end

    if start == nil then
        return nil
    end

    local startRow, startCol = start:start()
    local endRow, endCol = decl:start()
    return vim.trim(table.concat(vim.api.nvim_buf_get_text(bufnr, startRow, startCol, endRow, endCol, {}), " "))
end

local function isInParamList(node)
    local parent = node:parent()
    while parent do
        if parent:type() == M.Keys.ParamList then
            return true
        end
        parent = parent:parent()
    end

    return false
end

local function getParamName(param, bufnr)
    local node = param:field("declarator")[1]
    while node and node:type() ~= "identifier" do
        node = node:field("declarator")[1] or node:named_child(0)
    end

    return node and vim.treesitter.get_node_text(node, bufnr)
end

---Rebuild a parameter list for the `.cpp`: default values dropped, whitespace collapsed.
---@param paramsNode TSNode
---@param bufnr number
---@return string paramString e.g. `(int32 A, float B)`
---@return string[] paramNames
local function buildParamsText(paramsNode, bufnr)
    local skipNodes = { "(", ")", ",", "comment" }

    local params = {}
    local names = {}
    for param in paramsNode:iter_children() do
        local kind = param:type()
        if not vim.tbl_contains(skipNodes, kind) then
            local text = vim.treesitter.get_node_text(param, bufnr)
            if kind == M.Keys.OptionalParam then
                local last = param:field("declarator")[1] or param:field("type")[1]
                local startRow, startCol = param:start()
                local endRow, endCol = last:end_()
                text = table.concat(vim.api.nvim_buf_get_text(bufnr, startRow, startCol, endRow, endCol, {}), " ")
            end
            table.insert(params, (text:gsub("%s+", " ")))
            table.insert(names, getParamName(param, bufnr))
        end
    end

    return "(" .. table.concat(params, ", ") .. ")", names
end

---Read the function declaration under the cursor into parts (return type, name, parameters,
---`const`, specifiers) so `impl.lua` can write the `.cpp` version. The name is prefixed with
---`className::`.
---`Skip = true` means no body should be written (pure virtual, deleted, inline,
---`BlueprintImplementableEvent`).
---@param className string e.g. `AMyActor`
---@return DeclarationTemplate parts are missing when the cursor is not on a declaration
function M.GetDeclarationTemplate(className)
    ---@type DeclarationTemplate
    local result = {
        Skip = false,
        paramIdentifiers = {},
        ufunctionSpecifiers = {},
    }

    local success, queryInfo = M.PrepareForQuery()
    if not success then
        return result
    end

    local bufnr = queryInfo.bufnr
    local lang = queryInfo.lang

    local declarationRoot = getDeclarationRoot()
    if declarationRoot == nil then
        return result
    end

    local query = vim.treesitter.query.get(lang, "unreal_function_declaration")
    if query == nil then
        return result
    end

    for id, capturedNode, _ in query:iter_captures(declarationRoot, bufnr) do
        local queryId = query.captures[id]
        if queryId == M.Keys.Skip then
            result.Skip = true
            return result
        end

        if queryId == M.Keys.UfunctionSpecifier then
            local specifierName = vim.treesitter.get_node_text(capturedNode, bufnr)
            table.insert(result.ufunctionSpecifiers, specifierName)
        elseif not isInParamList(capturedNode) then
            local text = vim.treesitter.get_node_text(capturedNode, bufnr)
            if queryId == M.Keys.DeclName then
                result[M.Keys.DeclType] = getReturnType(capturedNode, bufnr)
                result[queryId] = className .. "::" .. text
            elseif queryId == M.Keys.DeclParams then
                local paramString, paramNames = buildParamsText(capturedNode, bufnr)
                result[queryId] = paramString
                result.paramIdentifiers = paramNames
            else
                result[queryId] = text
            end
        end
    end

    return result
end

---Closest `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` macro node at or above the cursor.
---@return TSNode?
local function getMacroRoot()
    local macroRoots = {
        "uclass_macro",
        "ustruct_macro",
        "ufunction_macro",
        "uproperty_macro",
    }

    local node = vim.treesitter.get_node()
    while node and not vim.tbl_contains(macroRoots, node:type()) do
        node = node:parent()
    end

    return node
end

---Read the macro under the cursor: the macro node, its name (e.g. `UPROPERTY`) and the
---specifiers and meta keys it already has, so they are not suggested twice.
---@return TSNode? macroNode nil when the cursor is not inside a macro
---@return string macroIdentifier
---@return ExistedMacroVariables existedVariables `{ arguments, metas }`
function M.GetMacro()
    local existedVariables = {
        arguments = {},
        metas = {},
    }

    local success, queryInfo = M.PrepareForQuery()
    if not success then
        return nil, "", existedVariables
    end

    local bufnr = queryInfo.bufnr
    local lang = queryInfo.lang

    local query = vim.treesitter.query.get(lang, "unreal_macro")
    if query == nil then
        return nil, "", existedVariables
    end

    local macroNode = nil
    local identifier = ""

    local node = getMacroRoot()
    if node == nil then
        return nil, "", existedVariables
    end

    for id, capturedNode, _ in query:iter_captures(node, bufnr) do
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

---Where to insert a new specifier in a macro, and how to join it to what is there.
---New specifiers go at the end, but always before `meta = (...)`;
---new meta keys go at the end inside `meta = (...)`.
---Example: in `UPROPERTY(EditAnywhere, meta = (ClampMin = 0))`, `BlueprintReadOnly` goes
---before `meta`, `ClampMax` goes after `ClampMin = 0`.
---@param macroNode TSNode
---@param isMeta boolean whether the new item is a meta key
---@return MacroAddType addType how to join: first item, append, prepend, or append inside meta
---@return number row 0-based
---@return number col 0-based
function M.GetNextMacroPosition(macroNode, isMeta)
    local types = require("unreal.types")
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
