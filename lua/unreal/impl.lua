local config = require('unreal.config')
local system = require('unreal.system')
local search = require('unreal.search')
local pathUtils = require('unreal.path_utils')
local treesitter = require('unreal.treesitter')
local log = require('unreal.log')

local info = config.info
local logLevel = vim.log.levels

local M = {}

---Generate a `.cpp` implementation stub for the function declaration under the cursor.
---Requires an open header file; jumps to the existing implementation instead of
---duplicating it if one is already present in the target `.cpp` file.
function M.ImplementFunction()
    local res = M.PrepareForFunctionImpl()
    if not res.success then
        log.Notify(res.err, logLevel.ERROR)
        return
    end

    local node = res.ts_node
    local cppFile = res.cppFile

    if node == nil or cppFile == nil then return end

    local className = treesitter.GetTypeName(node)
    if className == "" then
        log.Notify("Unable to find class name for implementation creation!", logLevel.ERROR)
        return
    end

    local declarationTemplate = treesitter.GetDeclarationTemplate(className)
    if next(declarationTemplate) == nil then
        log.Notify("Unable to create declaration template!", logLevel.ERROR)
        return
    end

    local parsed = M.ParseImplementation(declarationTemplate)
    local buf = system.OpenBuffer(cppFile)

    local implLine = search.FindImplementation(buf, parsed[2])
    if implLine == -1 then
        local insertLine = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, insertLine, insertLine, false, parsed)

        implLine = insertLine
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
            err =  "Cannot find corresponding treesitter node!",
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
        cppFile = cppFile
    }
end

---
---@param declaration table
---@return table
function M.ParseImplementation(declaration)
    local declTypeKey = treesitter.Keys.DeclType
    local declKeys = treesitter.Keys.DeclKeys

    local content = {}
    local declarationText = ""

    for _, keyName in ipairs(declKeys) do
        if declaration[keyName] ~= nil then
            local appending = declaration[keyName]
            local space = (#declarationText > 0 and keyName ~= "function.params") and " " or ""

            declarationText = declarationText .. space .. appending
        end
    end

    table.insert(content, "")
    table.insert(content, declarationText)

    if declaration[declTypeKey] == nil then
        local constructorParams = table.concat(declaration.paramIdentifiers, ", ")
        table.insert(content, "\t: Super(" .. constructorParams .. ")")
    end

    table.insert(content, "{")
    table.insert(content, "\t// TODO:")
    table.insert(content, "}")

    return content
end

return M
