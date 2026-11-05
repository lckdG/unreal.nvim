local config = require("unreal.config")
local system = require("unreal.system")
local engine = require("unreal.engine")
local pathUtils = require("unreal.path_utils")
local log = require("unreal.log")

local info = config.info
local logLevel = vim.log.levels

---Find `.uproject` files under the working directory and call `cb` with one of them.
---Errors if none, prompts if several, skips `cb` if the prompt is dismissed.
---@param cb fun(uprojectPath: string)
local function withUproject(cb)
    local files = pathUtils.FindUprojects({ nameOnly = false, upward = false })
    if #files == 0 then
        log.Notify("No uproject file found!", logLevel.ERROR)
    elseif #files == 1 then
        cb(files[1])
    else
        local ui = require("unreal.ui")
        ui.Select(ui.WrapList(files), { prompt = "Multiple uproject found, choose one" }, function(item)
            if item ~= nil then
                cb(item.value)
            end
        end)
    end
end

local M = {}

function M.init() end

---`:Unreal Project Open`: open the project in Unreal Editor.
---Needs an engine path (asks for one if unset). On Windows the `.uproject` opens with its
---default program; on Linux/Mac the engine's `UnrealEditor` starts with it.
---Shows an error if no `.uproject` is found or the editor program is missing.
function M.OpenUproject()
    if engine.EnsureEnginePath() == false then
        return
    end

    withUproject(function(projectPath)
        local ok, executeCmd = engine.GetExecuteCmd()
        if not ok then
            log.Notify("Engine executable not found!", logLevel.ERROR)
        else
            table.insert(executeCmd, projectPath)
            vim.fn.jobstart(executeCmd, { detach = true })
        end
    end)
end

---`:Unreal Build Clangd`: regenerate `compile_commands.json`, the file clangd reads to
---understand your code (include paths, defines). Run it after adding modules, plugins or files.
---Runs UnrealBuildTool in a terminal split, then copies the result into the working directory.
---Extra UnrealBuildTool arguments come from the `clangd_build_args` option.
---Needs an engine path (asks for one if unset). Shows an error if the build or copy fails.
function M.RebuildClangd()
    if engine.EnsureEnginePath() == false then
        return
    end

    local dotnet = engine.GetDotNetCmd()
    local buildTool = engine.GetUbtDll()
    if dotnet == nil or buildTool == nil then
        log.Notify("Unable to locate dotnet or UnrealBuildTool.dll", logLevel.WARN)
        return
    end

    withUproject(function(uprojectPath)
        local projectName = vim.fn.fnamemodify(uprojectPath, ":t:r")
        local projectEditor = projectName .. "Editor"

        local commandParts = {
            dotnet,
            buildTool,
            "-mode=GenerateClangDatabase",
        }

        commandParts = vim.iter({
            commandParts,
            config.GetClangdBuildArgs(),
            { "-project=" .. uprojectPath, "-game", "-engine", projectEditor, system.GetPlatform(), "Development" },
        })
            :flatten()
            :totable()

        vim.cmd("botright new")
        local termWin = vim.api.nvim_get_current_win()

        vim.fn.jobstart(commandParts, {
            term = true,
            on_exit = function(_, code)
                if vim.api.nvim_win_is_valid(termWin) then
                    vim.api.nvim_set_current_win(termWin)
                    vim.cmd("startinsert")
                end

                if code ~= 0 then
                    log.Notify("Rebuild Clangd failed (" .. code .. ")", logLevel.ERROR)
                    return
                end

                local sourceCC = vim.fs.joinpath(engine.EnginePath, info.CCFile)
                local destCC = vim.fs.joinpath(vim.fs.dirname(uprojectPath), info.CCFile)

                local ok, err = vim.uv.fs_copyfile(sourceCC, destCC)
                if ok then
                    log.Notify("Rebuild database successfully!", logLevel.INFO)
                else
                    log.Notify("Failed to copy compile_commands file: " .. tostring(err), logLevel.ERROR)
                end
            end,
        })
    end)
end

---`:Unreal Project Edit`: open the `.uproject` file (JSON with modules, plugins, engine version)
---in a buffer to edit it. No engine path needed. Several files: the user picks one.
function M.EditUproject()
    withUproject(function(path)
        vim.cmd.edit(vim.fn.fnameescape(path))
    end)
end

return M
