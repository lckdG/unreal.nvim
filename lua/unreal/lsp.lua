local log = require("unreal.log")
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
        desc = descLines,
    }
end

local M = {}

---@return vim.lsp.Client client
local function GetClangdClient()
    ---@type vim.lsp.Client
    local lspClient = vim.lsp.get_clients({ name = "clangd", bufnr = 0 })[1]
    return lspClient
end

---
---@param request MacroCompletionRequest
---@return table
function M.GetMacroCompletions(request)
    local lspClient = GetClangdClient()
    if lspClient == nil then
        log.Notify("Cannot find clangd client", logLevel.ERROR)
        return {}
    end

    local tempBufnr = require("unreal.system").CreateTempBuffer()

    local namespace = string.sub(request.identifier, 1, 2)
    local insertTerm = namespace .. "::"

    vim.api.nvim_buf_set_lines(tempBufnr, 0, 0, false, { insertTerm })
    vim.lsp.buf_attach_client(tempBufnr, lspClient.id)

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(tempBufnr),
        position = {
            line = 0,
            character = #insertTerm,
        },
        context = {
            triggerKind = 1, -- Invoked trigger
        },
    }

    local async = require("plenary.async")
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

return M
