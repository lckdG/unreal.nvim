local log = require("unreal.log")
local logLevel = vim.log.levels

local LSP_NOT_FOUND_ERROR = "Cannot find clangd client"

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

---@return vim.lsp.Client? client nil when clangd is not attached to the current buffer
local function GetClangdClient()
    ---@type vim.lsp.Client?
    local lspClient = vim.lsp.get_clients({ name = "clangd", bufnr = 0 })[1]
    return lspClient
end

---Ask clangd which specifiers exist for a macro. The engine declares them as fake C++ names
---(e.g. `UP::EditAnywhere` for UPROPERTY), so this types `UP::` in a hidden buffer and
---reads clangd's completions.
---Must run inside a plenary async function. Shows an error and returns `{}` on failure.
---@param request MacroCompletionRequest which macro, and specifiers to leave out
---@return unreal.UiEntry[] entries one per specifier, with its documentation
function M.GetMacroCompletions(request)
    local lspClient = GetClangdClient()
    if lspClient == nil then
        log.Notify(LSP_NOT_FOUND_ERROR, logLevel.ERROR)
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

function M.SwitchSourceHeader()
    local requestMethod = "textDocument/switchSourceHeader"
    local lspClient = GetClangdClient()

    if lspClient == nil then
        log.Notify(LSP_NOT_FOUND_ERROR, logLevel.ERROR)
        return
    ---@diagnostic disable-next-line param-type-mismatch
    elseif not lspClient:supports_method(requestMethod, 0) then
        log.Notify("Method not supported: " .. requestMethod, logLevel.ERROR)
        return
    end

    ---@diagnostic disable-next-line param-type-mismatch
    lspClient:request(requestMethod, vim.lsp.util.make_text_document_params(0), function(err, uri)
        if err or not uri or uri == "" then
            log.Notify("No matching source/header found", logLevel.WARN)
            return
        end

        vim.cmd.edit(vim.fn.fnameescape(vim.uri_to_fname(uri)))
    end)
end

return M
