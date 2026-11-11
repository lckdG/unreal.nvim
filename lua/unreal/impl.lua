local config = require("unreal.config")
local system = require("unreal.system")
local pathUtils = require("unreal.path_utils")
local treesitter = require("unreal.treesitter")
local log = require("unreal.helpers.log")

local info = config.info
local logLevel = vim.log.levels

local implementationOverride = { suffix = "_Implementation", type = nil, add = false }
local validationOverride = { suffix = "_Validate", type = "bool", add = true }

local specifierOverrides = {
    BlueprintNativeEvent = implementationOverride,
    Server = implementationOverride,
    Client = implementationOverride,
    NetMulticast = implementationOverride,
    WithValidation = validationOverride,
}

local M = {}

---`:Unreal Code Impl`: with the cursor on a function declaration in a header, write an
---empty implementation at the end of the matching `.cpp` and jump to it.
---If the function is already implemented there, it jumps to it instead.
---Unreal-specific cases: `BlueprintNativeEvent` and RPCs (`Server`, `Client`, `NetMulticast`)
---get a `_Implementation` function, `WithValidation` also gets `_Validate`.
---Shows an error outside a header or when no matching `.cpp` is found.
function M.ImplementFunction()
    local res = M.PrepareForFunctionImpl()
    if not res.success then
        log.Notify(res.err, logLevel.ERROR)
        return
    end

    local node = res.ts_node
    local cppFile = res.cppFile

    if node == nil or cppFile == nil then
        return
    end

    local className = treesitter.GetTypeName(node)
    if className == "" then
        log.Notify("Unable to find class name for implementation creation!", logLevel.ERROR)
        return
    end

    local declarationTemplate = treesitter.GetDeclarationTemplate(className)
    if declarationTemplate.Skip then
        log.Notify("Function is pure virtual, deleted or inline implemented", logLevel.ERROR)
        return
    elseif vim.tbl_contains(declarationTemplate.ufunctionSpecifiers, "BlueprintImplementableEvent") then
        log.Notify("Function should be implemented in blueprints", logLevel.WARN)
        return
    elseif declarationTemplate[treesitter.Keys.DeclName] == nil then
        log.Notify("Function does not have a name", logLevel.ERROR)
        return
    end

    local parsed, signalIndex = M.ParseImplementation(declarationTemplate)
    local buf = system.OpenBuffer(cppFile)

    local implLine = require("unreal.search").FindImplementation(buf, parsed[signalIndex])
    if implLine == -1 then
        local insertLine = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, insertLine, insertLine, false, parsed)

        implLine = insertLine + signalIndex
    else
        log.Notify("Function is already implemented at line " .. implLine, logLevel.INFO)
    end

    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { implLine, 0 })
    vim.cmd([[normal! zz]])
end

function M.PrepareForFunctionImpl()
    if vim.fn.expand("%:t:e") ~= info.HeaderExt then
        return {
            success = false,
            err = "Not a header file!",
            ts_node = nil,
            cppFile = nil,
        }
    end

    local node = vim.treesitter.get_node()
    if node == nil then
        return {
            success = false,
            err = "Cannot find corresponding treesitter node!",
            ts_node = nil,
            cppFile = nil,
        }
    end

    local cppFile = pathUtils.GetSourceHeader()
    if cppFile == nil then
        return {
            success = false,
            err = "Cannot find corresponding cpp file!",
            ts_node = nil,
            cppFile = nil,
        }
    end

    return {
        success = true,
        err = nil,
        ts_node = node,
        cppFile = cppFile,
    }
end

---Build one `.cpp` definition block (blank line, signature, `: Super(...)` for constructors, body).
---@param template DeclarationTemplate
---@param suffix string? appended to the function name, e.g. `_Implementation`
---@param typeOverride string? replaces the return type, e.g. `bool` for `_Validate`
---@return string[] lines
---@return number sigIndex index of the signature line in `lines`
local function constructFunctionBlock(template, suffix, typeOverride)
    local declTypeKey = treesitter.Keys.DeclType
    local declKeys = treesitter.DeclKeys

    local content = {}
    local declarationText = ""

    for _, keyName in ipairs(declKeys) do
        if template[keyName] ~= nil then
            local appending = template[keyName]
            local space = (#declarationText > 0 and not vim.tbl_contains(treesitter.NonSpaceKeys, keyName)) and " "
                or ""

            if keyName == treesitter.Keys.DeclName and suffix then
                appending = appending .. suffix
            elseif keyName == treesitter.Keys.DeclType and typeOverride then
                appending = typeOverride
            end

            declarationText = declarationText .. space .. appending
        end
    end

    table.insert(content, "")
    if template[treesitter.Keys.DeclTemplate] then
        table.insert(content, "template" .. template[treesitter.Keys.DeclTemplate])
    end

    table.insert(content, declarationText)
    local sigIndex = #content

    if template[declTypeKey] == nil and not template[treesitter.Keys.DeclName]:find("::~", 1, true) then
        local constructorParams = table.concat(template.paramIdentifiers, ", ")
        table.insert(content, "\t: Super(" .. constructorParams .. ")")
    end

    table.insert(content, "{")
    table.insert(content, "\t// TODO:")
    table.insert(content, "}")

    return content, sigIndex
end

---Write every function body a declaration needs. Usually one; Unreal specifiers can rename it
---(`BlueprintNativeEvent` -> `Foo_Implementation`) or add more (`WithValidation` -> `Foo_Validate`).
---@param declaration DeclarationTemplate
---@return string[] lines all bodies, ready to append to the `.cpp`
---@return number sigIndex the main signature line: searched to tell if it already exists, and where the cursor lands
function M.ParseImplementation(declaration)
    local mainImpl = { suffix = nil, type = nil }
    local additionalImpls = {}

    for _, specifier in ipairs(declaration.ufunctionSpecifiers) do
        local override = specifierOverrides[specifier]
        if override ~= nil then
            if override.add == false then
                mainImpl = override
            else
                table.insert(additionalImpls, override)
            end
        end
    end

    local content, sigIndex = constructFunctionBlock(declaration, mainImpl.suffix, mainImpl.type)

    for _, override in ipairs(additionalImpls) do
        local suffix = override.suffix
        local type = override.type

        local blockContent = constructFunctionBlock(declaration, suffix, type)

        vim.list_extend(content, blockContent)
    end

    return content, sigIndex
end

return M
