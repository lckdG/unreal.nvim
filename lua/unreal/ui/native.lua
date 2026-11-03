local M = {}

M.Input = vim.ui.input

---
---@param items unreal.UiEntry[]
---@param opts {prompt?: string}
---@param cb fun(value?: unreal.UiEntry)
function M.Select(items, opts, cb)
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
function M.FileSearch(searchArgs, opts)
    M.Input({ prompt = opts.prompt }, function(input)
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
function M.GrepSearch(searchArgs, opts)
    M.Input({ prompt = opts.prompt }, function(input)
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

return M
