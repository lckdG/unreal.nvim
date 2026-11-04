local NativeUiProvider = {}

function NativeUiProvider.Input(...)
    return vim.ui.input(...)
end

---`vim.ui.select` over `items`, showing `item.name`; `cb(nil)` when cancelled.
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

---Built-in file search: ask for part of a file name, run ripgrep once, list results in the
---quickfix list. The typed text is placed into the last argument, which must be the file
---name pattern: `*.ini` + `Game` -> `*Game*.ini`. Note: `searchArgs` is changed in place.
---@param searchArgs string[] `{ "rg", "--files", <scope args...> }`
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

---Built-in text search: ask for the text, run ripgrep once, list matches in the quickfix list.
---The text is passed after `--`, so a search such as `-Foo` is not read as an option.
---Note: `searchArgs` is changed in place.
---@param searchArgs string[] `{ "rg", "--vimgrep", "-S", <scope args...> }`
---@param opts {prompt?: string}
function NativeUiProvider.GrepSearch(searchArgs, opts)
    NativeUiProvider.Input({ prompt = opts.prompt }, function(input)
        if input == nil then
            return
        end

        vim.list_extend(searchArgs, { "--", input })
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

---Choose how the plugin shows pickers, prompts and search results.
---Extensions call this (Telescope does); you can pass your own provider with
---`Select`, `Input`, `FileSearch` and `GrepSearch`. `nil` goes back to the built-in UI.
---@param p unreal.UiProvider?
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

---Turn strings into `UiEntry` items for `Select`; `value` is the string, or its index when `indexAsValue`.
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
