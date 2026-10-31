local config = require('unreal.config')
local system = require('unreal.system')
local engine = require('unreal.engine')
local pathUtils = require('unreal.path_utils')
local log = require('unreal.log')

local info = config.info
local logLevel = vim.log.levels

local M = {}

function M.init()

end

---Open the `.uproject` file in the current directory with the OS default handler.
---Prompts to choose one if multiple are found; no-ops if none are found.
function M.OpenUproject()
    if engine.EnsureEnginePath() == false then
        return
    end

    local function OpenUproject_Internal(projectPath)
        local executeCmd = engine.GetExecuteCmd()
        table.insert(executeCmd, projectPath)
        vim.fn.jobstart(executeCmd, { detach = true })
    end

    local uprojectFiles = pathUtils.FindUprojects{ nameOnly = false }
    if #uprojectFiles == 0 then
        log.Notify("No uproject file found!", logLevel.ERROR)
    elseif #uprojectFiles == 1 then
        OpenUproject_Internal(uprojectFiles[1])
    else
        require('unreal.ui').SelectOptionsCb(
            "Multiple uproject found, choose one",
            uprojectFiles,
            OpenUproject_Internal
        )
    end
    M.SelectUproject(function (projectPath)
    end, { nameOnly = false })
end

---Regenerate `compile_commands.json` via UnrealBuildTool and copy it into the working directory.
---Uses `clangd_build_args` from setup() config for extra UBT arguments.
---Prompts for an engine path if none is set yet; aborts if still unresolved.
function M.RebuildClangd()
    if engine.EnsureEnginePath() == false then
        return
    end

    if engine.BuildTool == nil then
        log.Notify("No valid engine path found, aborting ", logLevel.WARN)
        return
    end

    local function RebuildClangd_Internal(uprojectPath)
        local projectName = vim.fn.fnamemodify(uprojectPath, ":t:r")
        local projectEditor = projectName .. "Editor"

        local buildTool = engine.BuildTool
        local buildCommand = "!dotnet " .. buildTool
                            .. " -mode=GenerateClangDatabase"
                            .. " " .. config.GetClangdBuildArgs()
                            .. " -project=" .. uprojectPath
                            .. " -game -engine " .. projectEditor
                            .. " " .. system.GetPlatform() .. " Development"
        vim.cmd(buildCommand)

        local sourceCC = vim.fs.joinpath(engine.EnginePath, info.CCFile)
        local destCC = vim.fs.joinpath(vim.fn.getcwd(), info.CCFile)

        local ok, err = vim.uv.fs_copyfile(sourceCC, destCC)
        if ok then
            log.Notify("Rebuild database successfully!", logLevel.INFO)
        else
            log.Notify("Failed to copy compile_commands file: " .. tostring(err), logLevel.ERROR)
        end
    end

    local uprojectFiles = pathUtils.FindUprojects{ nameOnly = false }
    if #uprojectFiles == 0 then
        log.Notify("No uproject file found!", logLevel.ERROR)
    elseif #uprojectFiles == 1 then
        RebuildClangd_Internal(uprojectFiles[1])
    else
        require('unreal.ui').SelectOptionsCb(
            "Multiple uproject found, choose one",
            uprojectFiles,
            RebuildClangd_Internal
        )
    end
end

return M
