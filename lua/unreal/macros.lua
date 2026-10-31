local log = require('unreal.log')
local treesitter = require('unreal.treesitter')

local logLevel = vim.log.levels

local function createCompletionEntry(rawEntry, exclusions)
    local function trim(str)
        local res, _ = string.gsub(str, "^%s(.-)%s*$", '%1')
        return res
    end

    local label = trim(rawEntry.label)
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
        name = label,
        desc = descLines
    }
end

local function getMacroCompletions(macroIdentifier, lspClient, exclusions, callback)
    local tempBufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(tempBufnr, "resolver")

    local namespace = string.sub(macroIdentifier, 1, 2)
    local insertTerm = namespace .. "::"

    vim.api.nvim_buf_set_lines(tempBufnr, 0, 0, false, { insertTerm })
    vim.lsp.buf_attach_client(tempBufnr, lspClient.id)

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

    vim.lsp.buf_request(tempBufnr, "textDocument/completion", params, function (err, result)
        if err ~= nil then
            print(err)
            callback(nil)
        else
            table.insert(exclusions, namespace)

            local entries = {}
            for _, item in ipairs(result.items) do
                local entry = createCompletionEntry(item, exclusions)
                if entry ~= nil then
                    table.insert(entries, entry)
                end
            end

            callback(entries)
        end
    end)

    vim.api.nvim_buf_delete(tempBufnr, { force = true })
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
    local macroNode, macroIdentifier, existedVariables = treesitter.GetMacro()

    if macroNode == nil then
        log.Notify(errorMsg, logLevel.ERROR)
        return
    end

    ---@type vim.lsp.Client
    local lspClient = vim.lsp.get_clients{ name = "clangd", bufnr = 0 }[1]
    getMacroCompletions(macroIdentifier, lspClient, existedVariables, function (completionList)
        if completionList == nil then
            return
        end

        require('unreal.ui').EntryPicker(completionList, function (entry)
            local _, _, endRow, endCol = macroNode:range()
            local insertRow = endRow
            local insertCol = endCol - 1

            local insertion = #existedVariables > 1 and ", " .. entry or entry
            vim.api.nvim_buf_set_text(0, insertRow, insertCol, insertRow, insertCol, { insertion })
            vim.api.nvim_win_set_cursor(0, { insertRow + 1, insertCol + #insertion })
        end)
    end)
end

return M
