local log = require("unreal.helpers.log")
local treesitter = require("unreal.treesitter")

local logLevel = vim.log.levels

---Insert a specifier into the macro at the position from `GetNextMacroPosition`,
---adding `, ` separators and a `meta = (...)` wrapper when needed, then move the cursor after it.
---@param macroNode TSNode
---@param value {text: string, isMeta: boolean}
local function addMacro(macroNode, value)
    local text = value.text
    local isMeta = value.isMeta

    local addType, addRow, addCol = treesitter.GetNextMacroPosition(macroNode, isMeta)

    local types = require("unreal.types")
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

---`:Unreal Code Macro`: with the cursor inside `UCLASS(...)`, `USTRUCT(...)`, `UFUNCTION(...)`
---or `UPROPERTY(...)`, pick a specifier (such as `EditAnywhere` or `BlueprintCallable`) and insert it.
---Specifiers already in the macro are not offered again. The picker uses the active UI
---(Telescope also previews each specifier's documentation).
---Needs clangd attached to the buffer; shows an error without it or outside a macro.
---The list comes from clangd reading the engine's `UObject/ObjectMacros.h`; some engine builds
---strip it, which gives an empty list. It is a helpful subset, not complete:
---see https://unreal-garden.com for every specifier.
function M.CompleteMacro()
    if require("unreal.system").HasClangdEnabled() == false then
        log.Notify("Clangd is not enabled for current buffer!", logLevel.ERROR)
        return
    end

    local errorMsg = "No valid macro under cursor detected"
    local macroNode, identifier, existedVariables = treesitter.GetMacro()

    if macroNode == nil then
        log.Notify(errorMsg, logLevel.ERROR)
        return
    end

    local lsp = require("unreal.lsp")

    local async = require("plenary.async")
    async.run(function()
        local namespaceCompletions = lsp.GetMacroCompletions({
            identifier = identifier,
            exclusions = existedVariables.arguments,
        })

        -- We need the UM:: here
        -- The rest are just for human readability
        local metaCompletions = lsp.GetMacroCompletions({
            identifier = "UMETA",
            exclusions = existedVariables.metas,
        })

        if #namespaceCompletions + #metaCompletions == 0 then
            return
        end

        local completionList = vim.list_extend(namespaceCompletions, metaCompletions)
        require("unreal.ui").Select(completionList, { prompt = "Complete macro: " }, function(entry)
            if entry == nil then
                return
            end
            addMacro(macroNode, entry)
        end)
    end, function() end)
end

return M
