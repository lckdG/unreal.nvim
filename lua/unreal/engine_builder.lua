local log = require("unreal.log")
local logLevels = vim.log.levels

local EngineBuilder = {}

function EngineBuilder.Checkout()
    local config = require("unreal.config")
    local engineSource = config.opts.engine_source
    local cloneDir = engineSource.clone_dir

    if cloneDir == nil or not require("unreal.path_utils").Exists(cloneDir) then
        log.Notify("Error: Engine source folder not found " .. tostring(cloneDir), logLevels.ERROR)
        return
    end

    local system = require("unreal.system")
    system.GetUnrealTags(function(tags)
        require("unreal.ui").Select(tags, { prompt = "Select tag to checkout: " }, function (item)
            if item == nil then
                return
            end

            local command = {
                "git",
                "clone",
                "--depth",
                "1",
                "--branch",
                item.value,
                engineSource.git_url,
                vim.fs.joinpath(cloneDir, item.value),
            }

            vim.cmd("botright new")
            local termWin = vim.api.nvim_get_current_win()
            vim.fn.jobstart(command, {
                term = true,
                on_exit = function(_, _)
                    if vim.api.nvim_win_is_valid(termWin) then
                        vim.api.nvim_set_current_win(termWin)
                        vim.cmd("startinsert")
                    end
                end,
            })
        end)
    end)
end

return EngineBuilder
