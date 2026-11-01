local log = require('unreal.log')
local treesitter = require('unreal.treesitter')

local logLevel = vim.log.levels

local function createCompletionEntry(rawEntry, namespace, exclusions)
    local label = vim.trim(rawEntry.label)
    if vim.tbl_contains(exclusions, label) then
        return nil
    end

    local desc = ""
    if rawEntry["documentation"] then
        if type(rawEntry.documentation) == "string" then
            desc = rawEntry.documentation
        else
            desc = rawEntry.documentation.value
        end
    end

    local descLines = vim.split(desc, "\n")

    return {
        name = namespace .. "::" .. label,
        value = { text = label, isMeta = namespace == "UM" },
        desc = descLines
    }
end

---
---@param request MacroCompletionRequest
local function getMacroCompletions(request)
    local tempBufnr = require('unreal.system').CreateTempBuffer()

    local namespace = string.sub(request.identifier, 1, 2)
    local insertTerm = namespace .. "::"

    vim.api.nvim_buf_set_lines(tempBufnr, 0, 0, false, { insertTerm })
    vim.lsp.buf_attach_client(tempBufnr, request.lspClient.id)

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(tempBufnr),
        position = {
            line = 0,
            character = #insertTerm
        },
        context = {
            triggerKind = 1, -- Invoked trigger
        }
    }

    local async = require('plenary.async')
    local requestLsp = async.wrap(function(bufnr, method, param, callback)
        vim.lsp.buf_request(bufnr, method, param, callback)
    end, 4)

    local err, result = requestLsp(tempBufnr, "textDocument/completion", params)
    vim.api.nvim_buf_delete(tempBufnr, { force = true })

    if err ~= nil then
        log.Notify("Completion request error: " .. (err.message or vim.inspect(err)), logLevel.ERROR)
        return {}
    end

    local exclusions = vim.list_extend({ namespace }, request.exclusions)
    local entries = {}

    for _, item in ipairs(result and (result.items or result) or {}) do
        local entry = createCompletionEntry(item, namespace, exclusions)
        if entry ~= nil then
            table.insert(entries, entry)
        end
    end

    return entries
end

---
---@param macroNode TSNode
---@param value table
local function addMacro(macroNode, value)
    local text = value.text
    local isMeta = value.isMeta

    local addType, addRow, addCol = treesitter.GetNextMacroPosition(macroNode, isMeta)

    local types = require('unreal.types')
    local content = text

    if isMeta then
        if addType == types.MACRO_ADD_TYPE.AppendMeta then
            content = ", " .. content
        else
            content = "meta = (" .. text .. ")"
            if addType == types.MACRO_ADD_TYPE.Append then
                content = ", " .. content
            end
        end
    elseif addType == types.MACRO_ADD_TYPE.Append then
        content = ", " .. content
    elseif addType == types.MACRO_ADD_TYPE.Prepend then
        content = content .. ", "
    end

    vim.api.nvim_buf_set_text(0, addRow, addCol, addRow, addCol, { content })
    vim.api.nvim_win_set_cursor(0, { addRow + 1, addCol + #content })
end

local M = {}

---Complete a `UCLASS`/`USTRUCT`/`UFUNCTION`/`UPROPERTY` attribute under the cursor via telescope.
---Requires an attached clangd client; silently no-ops without one or if no macro is under the cursor.
---Completions are pulled from the IntelliSense-only specifier namespaces declared in
---`UObject/ObjectMacros.h`; this header can be missing/stripped in some engine builds, in
---which case results are empty. Treat the specifier list there as a reference, not exhaustive --
---see unreal-garden (https://unreal-garden.com) for the complete set of specifiers per macro.
function M.CompleteMacro()
    if require('unreal.system').HasClangdEnabled() == false then
        log.Notify("Clangd is not enabled for current buffer!", logLevel.ERROR)
        return
    end

    local errorMsg = "No valid macro under cursor detected"
    local macroNode, identifier, existedVariables = treesitter.GetMacro()

    if macroNode == nil then
        log.Notify(errorMsg, logLevel.ERROR)
        return
    end

    ---@type vim.lsp.Client
    local lspClient = vim.lsp.get_clients{ name = "clangd", bufnr = 0 }[1]

    local async = require('plenary.async')
    async.run(function()
        local namespaceCompletions = getMacroCompletions{ identifier = identifier, lspClient = lspClient, exclusions = existedVariables.arguments }

        -- We need the UM:: here
        -- The rest are just for human readability
        local metaCompletions = getMacroCompletions{ identifier = "UMETA", lspClient = lspClient, exclusions = existedVariables.metas }

        if #namespaceCompletions + #metaCompletions == 0 then
            return
        end

        local completionList = vim.list_extend(namespaceCompletions, metaCompletions)
        require('unreal.ui').EntryPicker(completionList, function (entry)
            if entry == nil then return end
            addMacro(macroNode, entry)
        end)
    end, function() end)
end

return M
