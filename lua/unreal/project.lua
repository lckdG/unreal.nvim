local config = require("unreal.config")
local system = require("unreal.system")
local engine = require("unreal.engine")
local pathUtils = require("unreal.path_utils")
local log = require("unreal.log")

local info = config.info
local logLevel = vim.log.levels

local M = {}
M.ProjectRoot = nil
M.UprojectPath = nil

local function sendToQuickfix(errors)
    if errors and #errors > 0 then
        vim.fn.setqflist(errors, " ")
        vim.cmd.copen()
    end
end

function M.init()
    M.ProjectRoot = pathUtils.GetProjectRoot()
    M.FindDefaultUproject()

    local augroup = vim.api.nvim_create_augroup("unreal.nvim.project", { clear = true })
    vim.api.nvim_create_autocmd("DirChanged", {
        group = augroup,
        callback = function()
            local lastRoot = M.ProjectRoot
            M.ProjectRoot = pathUtils.GetProjectRoot()

            if M.ProjectRoot ~= lastRoot then
                M.UprojectPath = nil
                M.FindDefaultUproject()

                engine.reset()
            end
        end,
    })
end

---Pick a `.uproject` from the project folder without asking (subfolders are not searched).
---With several, one is picked; with none, the first project command searches instead.
function M.FindDefaultUproject()
    local found = {}
    for name, kind in vim.fs.dir(M.ProjectRoot) do
        if kind == "file" and vim.fs.ext(name) == "uproject" then
            table.insert(found, vim.fs.joinpath(M.ProjectRoot, name))
        end
    end

    if #found >= 1 then
        table.sort(found)
        M.UprojectPath = found[1]
    end
end

---Find `.uproject` files under the project folder (see `path_utils.GetProjectRoot`)
---and call `cb` with one of them.
---Errors if none, prompts if several, skips `cb` if the prompt is dismissed.
---@param cb fun(uprojectPath: string?)
function M.SelectUproject(cb)
    local files = pathUtils.FindUprojects({ path = M.ProjectRoot, nameOnly = false })
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

---`:Unreal Project Select`: choose which `.uproject` the other commands use.
---The choice is kept until Neovim closes or the working directory moves to another project.
function M.SelectUproject_User()
    M.SelectUproject(function(path)
        if pathUtils.Exists(path) then
            M.UprojectPath = path
        else
            log.Notify("Selected path is invalid", logLevel.WARN)
        end
    end)
end

---Run `callback` once a `.uproject` is chosen for this session.
---If none is chosen yet, finds one first (asking when there are several).
---@param callback fun()
function M.EnsureUproject(callback)
    if not M.UprojectPath or M.UprojectPath == "" then
        M.SelectUproject(function(path)
            if path and path ~= "" then
                M.UprojectPath = path
                callback()
            else
                log.Notify("Unable to determine .uproject file\nSet it manually", logLevel.WARN)
            end
        end)
    else
        callback()
    end
end

---`:Unreal Project Open`: open the project in Unreal Editor.
---Uses the engine the `.uproject` asks for (see `engine.FindEngineTools`).
---Shows an error if no `.uproject` is found or the engine has no `UnrealEditor` program.
function M.OpenUproject()
    M.EnsureUproject(function()
        local uprojectPath = M.UprojectPath
        engine.FindEngineTools(uprojectPath, function(tools)
            if tools and tools.EngineExe then
                local executeCmd = tools.EngineExe
                table.insert(executeCmd, uprojectPath)
                vim.fn.jobstart(executeCmd, { detach = true })
            else
                log.Notify("Unable to retrieve engine tools!", logLevel.ERROR)
            end
        end)
    end)
end

---`:Unreal Build Clangd`: regenerate `compile_commands.json`, the file clangd reads to
---understand your code (include paths, defines). Run it after adding modules, plugins or files.
---Runs UnrealBuildTool in a terminal split, then copies the result next to the `.uproject`.
---Extra UnrealBuildTool arguments come from the `clangd_build_args` option.
---Runs the engine's `RunUBT` script (`Engine/Build/BatchFiles/RunUBT.sh`, `.bat` on Windows), which
---sets up the engine's `dotnet` and compiles UnrealBuildTool itself when needed, so it also works on an
---engine built from source before the editor is compiled. Shows an error if the build or copy fails.
function M.RebuildClangd()
    M.EnsureUproject(function()
        local uprojectPath = M.UprojectPath
        engine.FindEngineTools(uprojectPath, function(tools)
            if tools and tools.UnrealBuildTool then
                local projectName = vim.fn.fnamemodify(uprojectPath, ":t:r")
                local projectEditor = projectName .. "Editor"

                local buildTool = tools.UnrealBuildTool

                local commandParts = {
                    buildTool,
                    "-mode=GenerateClangDatabase",
                }

                commandParts = vim.iter({
                    commandParts,
                    config.GetClangdBuildArgs(),
                    {
                        "-project=" .. uprojectPath,
                        "-game",
                        "-engine",
                        projectEditor,
                        system.GetPlatform(),
                        "Development",
                    },
                })
                    :flatten()
                    :totable()

                require("unreal.job").Start(commandParts, function(code, errors)
                    if code ~= 0 then
                        log.Notify("Rebuild Clangd failed (" .. code .. ")", logLevel.ERROR)
                        sendToQuickfix(errors)
                        return
                    end

                    local sourceCC = vim.fs.joinpath(tools.RootDir, info.CCFile)
                    local destCC = vim.fs.joinpath(vim.fs.dirname(uprojectPath), info.CCFile)

                    local ok, err = vim.uv.fs_copyfile(sourceCC, destCC)
                    if ok then
                        log.Notify("Rebuild database successfully!", logLevel.INFO)
                    else
                        log.Notify("Failed to copy compile_commands file: " .. tostring(err), logLevel.ERROR)
                    end
                end)
            else
                log.Notify("Unable to retrieve engine tools!", logLevel.ERROR)
            end
        end)
    end)
end

---`:Unreal Project Edit`: open the `.uproject` file (JSON with modules, plugins, engine version)
---in a buffer to edit it. No engine needed. Several files: the user picks one.
function M.EditUproject()
    M.EnsureUproject(function()
        local editPath = vim.fn.fnameescape(M.UprojectPath)
        vim.cmd.edit(editPath)
    end)
end

---`:Unreal Build Config`: pick a `BuildConfiguration.xml` (UnrealBuildTool settings) to open:
---the project's and engine's (when a `.uproject` is chosen) and your user ones.
---If the engine is not found, it asks for the engine folder first.
function M.EditBuildConfiguration()
    if M.UprojectPath then
        M.EnsureUproject(function()
            engine.FindEngineTools(M.UprojectPath, function(tools)
                M.ChooseBuildConfigFile(tools)
            end)
        end)
    else
        M.ChooseBuildConfigFile(nil)
    end
end

---List the `BuildConfiguration.xml` locations and open the one picked; a missing one is created after a confirm.
---@param engineTools unreal.EngineTools? adds the engine's file when given
function M.ChooseBuildConfigFile(engineTools)
    local availablePaths = {}

    if M.UprojectPath then
        local item = pathUtils.GetProjectBuildConfig(M.UprojectPath)
        table.insert(availablePaths, item)
    end

    local userBuildConfigs = pathUtils.GetUserBuildConfig()
    if userBuildConfigs then
        vim.list_extend(availablePaths, userBuildConfigs)
    end

    if engineTools and engineTools.BuildConfig ~= nil then
        table.insert(availablePaths, { name = "Engine Config", value = engineTools.BuildConfig })
    end

    local ui = require("unreal.ui")
    ui.Select(availablePaths, { prompt = "Choose configuration file to edit: " }, function(item)
        if item then
            local path = item.value
            if pathUtils.Exists(path) then
                vim.cmd.edit(vim.fn.fnameescape(path))
            else
                local choice = vim.fn.confirm("File does not exist, do you want to create one?", "Yes\nNo", 1)
                if choice == 1 then
                    M.CreateBuildConfiguration(path)
                end
            end
        end
    end)
end

---Open a new `BuildConfiguration.xml` with a minimal template (UnrealBuildTool rejects an empty file).
---Written when you save. Already open in a buffer: switches to it.
---@param path string full path of the file to create
function M.CreateBuildConfiguration(path)
    local editPath = vim.fn.fnameescape(path)
    local bufnr = vim.fn.bufnr(editPath)
    if bufnr ~= -1 then
        vim.cmd.buffer(bufnr)
    else
        vim.fn.mkdir(vim.fs.dirname(path), "p")

        vim.cmd.edit(editPath)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            '<?xml version="1.0" encoding="utf-8" ?>',
            '<Configuration xmlns="https://www.unrealengine.com/BuildConfiguration">',
            "</Configuration>",
        })
    end
end

function M.BuildEditor()
    M.EnsureUproject(function()
        local uprojectPath = M.UprojectPath
        engine.FindEngineTools(uprojectPath, function(tools)
            if tools and tools.UnrealBuildTool then
                local projectName = vim.fn.fnamemodify(uprojectPath, ":t:r")
                local projectEditor = projectName .. "Editor"

                local buildTool = tools.UnrealBuildTool

                local commandParts = {
                    buildTool,
                    projectEditor,
                    system.GetPlatform(),
                    "Development",
                    "-project=" .. uprojectPath,
                    "-WaitMutex",
                }

                require("unreal.job").Start(commandParts, function(code, errors)
                    if code ~= 0 then
                        log.Notify("Build editor failed (" .. code .. ")", logLevel.ERROR)
                        sendToQuickfix(errors)
                        return
                    end
                end)
            else
                log.Notify("Unable to retrieve engine tools!", logLevel.ERROR)
            end
        end)
    end)
end

function M.BuildEditorClean()
    M.EnsureUproject(function()
        local uprojectPath = M.UprojectPath
        engine.FindEngineTools(uprojectPath, function(tools)
            if tools and tools.UnrealBuildTool then
                local projectName = vim.fn.fnamemodify(uprojectPath, ":t:r")
                local projectEditor = projectName .. "Editor"

                local buildTool = tools.UnrealBuildTool

                local commandParts = {
                    buildTool,
                    projectEditor,
                    system.GetPlatform(),
                    "Development",
                    "-project=" .. uprojectPath,
                    "-Rebuild",
                    "-WaitMutex",
                }

                require("unreal.job").Start(commandParts, function(code, errors)
                    if code ~= 0 then
                        log.Notify("Clean build editor failed (" .. code .. ")", logLevel.ERROR)
                        sendToQuickfix(errors)
                        return
                    end
                end)
            else
                log.Notify("Unable to retrieve engine tools!", logLevel.ERROR)
            end
        end)
    end)
end

return M
