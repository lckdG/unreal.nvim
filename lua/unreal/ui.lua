local NativeUiProvider = {}

function NativeUiProvider.Input(...)
    return vim.ui.input(...)
end

---
---@param items unreal.UiEntry[]
---@param opts {prompt?: string}
---@param cb fun(value?: unreal.UiEntry)
function NativeUiProvider.Select(items, opts, cb)
    vim.ui.select(items, {
        prompt = opts.prompt,
        format_item = function(item)
            return item.name
        end,
    }, function(choice)
        cb(choice)
    end)
end

---
---@param searchArgs string[]
---@param opts {prompt?: string}
function NativeUiProvider.FileSearch(searchArgs, opts)
    NativeUiProvider.Input({ prompt = opts.prompt }, function(input)
        if input == nil then
            return
        end

        searchArgs[#searchArgs] = "*" .. input .. searchArgs[#searchArgs]
        vim.system(searchArgs, function(exitInfo)
            vim.schedule(function()
                if exitInfo.code > 1 then
                    require("unreal.log").Notify(exitInfo.stderr, vim.log.levels.ERROR)
                    return
                end

                local lines = vim.split(exitInfo.stdout, "\n", { trimempty = true })
                vim.fn.setqflist({}, " ", { title = opts.prompt or "File search output", lines = lines, efm = "%f" })
                vim.cmd.copen()
            end)
        end)
    end)
end

---
---@param searchArgs string[]
---@param opts {prompt?: string}
function NativeUiProvider.GrepSearch(searchArgs, opts)
    NativeUiProvider.Input({ prompt = opts.prompt }, function(input)
        if input == nil then
            return
        end

        table.insert(searchArgs, 4, "input")
        vim.system(searchArgs, function(exitInfo)
            vim.schedule(function()
                if exitInfo.code > 1 then
                    require("unreal.log").Notify(exitInfo.stderr, vim.log.levels.ERROR)
                    return
                end

                local lines = vim.split(exitInfo.stdout, "\n", { trimempty = true })
                vim.fn.setqflist(
                    {},
                    " ",
                    { title = opts.prompt or "Grep search output", lines = lines, efm = "%f:%l:%c:%m" }
                )
                vim.cmd.copen()
            end)
        end)
    end)
end

local Ui = {}

---@type unreal.UiProvider
Ui.provider = NativeUiProvider

function Ui.Use(p)
    Ui.provider = p or NativeUiProvider
end

function Ui.Select(...)
    return Ui.provider.Select(...)
end

function Ui.Input(...)
    return Ui.provider.Input(...)
end

function Ui.FileSearch(...)
    return Ui.provider.FileSearch(...)
end

function Ui.GrepSearch(...)
    return Ui.provider.GrepSearch(...)
end

---
---@param items string[]
---@param indexAsValue boolean?
---@return unreal.UiEntry[]
function Ui.WrapList(items, indexAsValue)
    local result = {}

    for index, item in ipairs(items) do
        local itemValue = indexAsValue and index or item
        table.insert(result, { name = item, value = itemValue, desc = "" })
    end

    return result
end

return Ui
