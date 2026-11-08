---@param config ConfigOpts
local function createCommands(config)
    local subcommands = {
        Engine = {
            SetPath = require("unreal.engine").SetEnginePath_User,
            ClearPath = require("unreal.engine").ClearEnginePath_User,
            Checkout = require("unreal.engine_builder").Checkout,
            Build = require("unreal.engine_builder").Build,
        },
        Project = {
            Open = require("unreal.project").OpenUproject,
            Edit = require("unreal.project").EditUproject,
            Select = require("unreal.project").SelectUproject_User,
        },
        Build = {
            Clangd = require("unreal.project").RebuildClangd,
            Config = require("unreal.project").EditBuildConfiguration,
            Editor = require("unreal.project").BuildEditor,
            CleanEditor = require("unreal.project").BuildEditorClean,
        },
        Code = {
            Impl = require("unreal.impl").ImplementFunction,
            Macro = require("unreal.macros").CompleteMacro,
            SwitchSourceHeader = require("unreal.search").SwitchSourceHeader,
        },
        Search = {
            Files = require("unreal.search").FindSource,
            Grep = require("unreal.search").GrepSource,
        },
    }

    vim.api.nvim_create_user_command(config.command_lead, function(opts)
        local args = opts.fargs

        local group = subcommands[args[1]]
        local func = group ~= nil and #args == 2 and group[args[2]] or nil

        if func ~= nil then
            func()
            return
        end

        require("unreal.log").Notify("Error: unavailable command " .. opts.args, vim.log.levels.ERROR)
    end, {
        nargs = "+",
        complete = function(arg_lead, cmdline)
            local args = vim.split(cmdline, "%s+", { trimempty = true })
            local level = #args - (arg_lead == "" and 0 or 1)

            local pool = level == 1 and subcommands or level == 2 and subcommands[args[2]] or {}
            local keys = vim.tbl_filter(function(k)
                return vim.startswith(k, arg_lead)
            end, vim.tbl_keys(pool))
            table.sort(keys)

            return keys
        end,
    })
end

---@param config ConfigOpts
local function createAbbrevs(config)
    local cmd_abbrevs = config.cmd_abbreviations
    if cmd_abbrevs == nil then
        return
    end

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
