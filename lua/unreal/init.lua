local M = {}
M.CommandLead = "Unreal"

---Entry point for the plugin. Applies config, then registers the `:Unreal` command.
---@param opts ConfigOpts?
function M.setup(opts)
    require('unreal.config').config(opts, M.CommandLead)
    M.CreateCommands()
end

local function SetEnginePath()
    vim.ui.input({ prompt = "Enter Unreal path: ", completion = "dir" }, function (input)
        require('unreal.config').SetEnginePath({ path = input, silent = false, savePath = true })
    end)
end


function M.CreateCommands()
    local subcommands = {
        SetEnginePath = SetEnginePath,
        OpenProject = require('unreal.functions').OpenUproject,
        RebuildClangd = require('unreal.functions').RebuildClangd,
        SwitchSourceHeader = require('unreal.functions').SwitchSourceHeader,
        CreateImpl = require('unreal.functions').ImplementFunction,
        CompleteMacro = require('unreal.functions').CompleteMacro,
        FindSource = require('unreal.functions').FindSource,
        GrepSource = require('unreal.functions').GrepSource,
    }

    vim.api.nvim_create_user_command(M.CommandLead, function (opts)
        local arg = opts.args
        local func = subcommands[arg]
        if func ~= nil then
            func()
        else
            require('unreal.logs').Notify("Error: unavailable command " .. arg, vim.log.levels.ERROR)
        end
    end, {
        nargs = 1,
        complete = function (arg_lead, cmdline, cursor_pos)
            return vim.tbl_keys(subcommands)
        end
    })
end

function M.CreateAbbrevs()
    local cabbr = vim.cmd.cabbrev
    local iabbr = vim.cmd.iabbrev

    cabbr("uo"  , M.CommandLead .. " OpenProject")
    cabbr("uc"  , M.CommandLead .. " RebuildClangd")
    cabbr("uss" , M.CommandLead .. " SwitchSourceHeader")
    cabbr("uci" , M.CommandLead .. " CreateImpl")
    cabbr("ucm" , M.CommandLead .. " CompleteMacro")
    cabbr("ufs", M.CommandLead .. " FindSource")
    cabbr("ugs", M.CommandLead .. " GrepSource")
end

return M
