local function SetEnginePath()
    vim.ui.input({ prompt = "Enter Unreal path: ", completion = "dir" }, function (input)
        require('unreal.config').SetEnginePath{ path = input, silent = false, savePath = true }
    end)
end

---@param config ConfigOpts
local function createCommands(config)
    local subcommands = {
        SetEnginePath = SetEnginePath,
        OpenProject = require('unreal.project').OpenUproject,
        RebuildClangd = require('unreal.project').RebuildClangd,
        SwitchSourceHeader = require('unreal.search').SwitchSourceHeader,
        CreateImpl = require('unreal.impl').ImplementFunction,
        CompleteMacro = require('unreal.macros').CompleteMacro,
        FindSource = require('unreal.search').FindSource,
        GrepSource = require('unreal.search').GrepSource,
    }

    vim.api.nvim_create_user_command(config.command_lead, function (opts)
        local arg = opts.args
        local func = subcommands[arg]
        if func ~= nil then
            func()
        else
            require('unreal.log').Notify("Error: unavailable command " .. arg, vim.log.levels.ERROR)
        end
    end, {
        nargs = 1,
        complete = function (arg_lead, cmdline, cursor_pos)
            return vim.tbl_keys(subcommands)
        end
    })
end

---@param config ConfigOpts
local function createAbbrevs(config)
    local cmd_abbrevs = config.cmd_abbreviations
    if cmd_abbrevs == nil then return end

    local cabbr = vim.cmd.cabbrev
    local command_lead = config.command_lead

    for abbrev, command in pairs(cmd_abbrevs) do
        cabbr(abbrev, command_lead .. " " .. command)
    end
end

local M = {}

---@param config ConfigOpts
function M.init(config)
    createCommands(config)
    createAbbrevs(config)
end

return M
