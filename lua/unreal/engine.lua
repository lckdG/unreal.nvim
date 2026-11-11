local system = require("unreal.system")
local pathUtils = require("unreal.path_utils")
local helpers = require("unreal.helpers")

local platform = system.GetPlatform()
local ext = platform == "Win64" and ".bat" or ".sh"

--#region Utility functions

---@param path string
local function readInstalledJson(path)
    local result = {}

    if helpers.path.Exists(path) then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()

            local ok, data =
                pcall(vim.json.decode, content, { luanil = { object = true, array = true }, skip_comments = true })

            if not ok then
                return result
            end

            local list = data["InstallationList"]
            if list then
                for _, item in ipairs(list) do
                    local name = item["AppName"]
                    local location = item["InstallLocation"]

                    table.insert(result, { id = name, path = location, kind = "launcher" })
                end
            end
        end
    end

    return result
end

---@param path string
local function readInstalledIni(path)
    local result = {}

    if helpers.path.Exists(path) then
        local startRead = false

        for line in io.lines(path) do
            line = vim.trim(line)
            if line ~= "" and not line:match("^[#^;]") then
                local section = line:match("^%[(.+)%]$")

                if section then
                    startRead = section == "Installations"
                elseif startRead then
                    local key, val = line:match("^([^=]+)=(.*)$")
                    if key and val then
                        table.insert(result, { id = key, path = val, kind = "source" })
                    end
                end
            end
        end
    end

    return result
end

local function readInstalledReg(path, cb)
    local result = {}

    vim.system({ "reg", "query", path }, { text = true }, function(exitInfo)
        vim.schedule(function()
            if exitInfo.code ~= 0 then
                helpers.log.Notify(
                    "Error when reading Unreal's Registry(" .. exitInfo.code .. "): " .. exitInfo.stderr,
                    vim.log.levels.ERROR
                )
            else
                local lines = vim.split(exitInfo.stdout, "\r?\n")
                for _, line in ipairs(lines) do
                    line = vim.trim(line)
                    -- Line format: <BUILD_ID> REG_SZ <LOCATION>
                    local id, location = line:match("^(%S+)%s+REG_SZ%s+(.*)$")
                    if id then
                        table.insert(result, { id = id, path = location, kind = "source" })
                    end
                end
            end

            cb(result)
        end)
    end)
end

--#endregion

local M = {}

---Engine source tree the working directory is inside; its projects (native projects)
---use it without needing `EngineAssociation`. nil outside an engine tree.
---@type string?
M.NativeEngine = nil

---Absolute folders of the native projects, found through the engine's `.uprojectdirs` files
---(e.g. `/ue/Games/MyGame`). nil without a native engine.
---@type string[]?
M.NativeProjects = nil

M.OverrideEnginePath = nil

function M.init()
    M.RefreshNativeProjects()

    local files = pathUtils.FindEngineInstalledFiles()
    M.FindInstalled(files)
end

function M.RefreshNativeProjects()
    M.NativeEngine = nil
    M.NativeProjects = nil

    local nativeEngineRoot = pathUtils.FindNativeEngineRoot()
    if nativeEngineRoot ~= nil then
        M.NativeEngine = nativeEngineRoot
        M.ParseNativeProjects()
    end
end

function M.ParseNativeProjects()
    M.NativeProjects = {}

    local filePaths = pathUtils.GetUprojectdirsFiles(M.NativeEngine)
    for _, filePath in ipairs(filePaths) do
        local file = io.open(filePath, "r")
        if file then
            for line in file:lines() do
                line = vim.trim(line)
                if line ~= "" and line:sub(1, 1) ~= ";" then
                    M.DiscoverNativeProjects(line)
                end
            end

            file:close()
        end
    end
end

function M.DiscoverNativeProjects(directory)
    if not M.NativeEngine then
        return
    end

    local absoluteDir = vim.fs.normalize(vim.fs.joinpath(M.NativeEngine, directory))
    for name, type in vim.fs.dir(absoluteDir, { depth = 2 }) do
        if type == "file" and vim.fs.ext(name) == "uproject" then
            local projectDir = vim.fs.normalize(vim.fs.joinpath(absoluteDir, vim.fs.dirname(name)))

            if not helpers.list.StrContains(M.NativeProjects, projectDir, platform == "Linux") then
                table.insert(M.NativeProjects, projectDir)
            end
        end
    end
end

---Find installed engine directories from config/registry files
---@param files table
function M.FindInstalled(files)
    M.InstalledEngines = {}

    for _, item in ipairs(files) do
        local list
        if item.type == "json" then
            list = readInstalledJson(item.path)
            M.AppendEngines(list)
        elseif item.type == "ini" then
            list = readInstalledIni(item.path)
            M.AppendEngines(list)
        elseif item.type == "reg" then
            readInstalledReg(item.path, M.AppendEngines)
        end
    end
end

function M.AppendEngines(items)
    for _, item in ipairs(items) do
        local id = item.id
        local path = item.path
        if M.FindEngine(id) == nil and M.IsRootEngineDirValid(path) then
            table.insert(M.InstalledEngines, item)
        end
    end
end

function M.FindEngine(id)
    if id == nil then
        return nil
    end

    local match = vim.iter(M.InstalledEngines):find(function(item)
        return item.id == id or item.id == "UE_" .. id
    end)

    return match
end

---`:Unreal Engine SetPath`: ask for an Unreal Engine folder and use it for every command,
---instead of the engine the `.uproject` asks for. Useful when the engine is not found automatically.
---Kept until `:Unreal Engine ClearPath`, a move to another project folder, or Neovim closes.
---Warns and keeps the old value if the folder has no readable `Engine/Build/Build.version`.
function M.SetEnginePath_User()
    M.InputEnginePath(function(path)
        if path and M.IsRootEngineDirValid(path) then
            M.OverrideEnginePath = path
            helpers.log.Notify("Override engine path is set!", vim.log.levels.INFO)
        else
            helpers.log.Notify("Input path is invalid, aborting...", vim.log.levels.WARN)
        end
    end)
end

---`:Unreal Engine ClearPath`: forget the folder set with `:Unreal Engine SetPath`,
---so commands go back to the engine the `.uproject` asks for.
function M.ClearEnginePath_User()
    M.OverrideEnginePath = nil
    helpers.log.Notify("Override engine path is cleared!", vim.log.levels.INFO)
end

---Build the path of the script that runs UnrealBuildTool inside an engine root:
---`Engine/Build/BatchFiles/RunUBT.sh` (`RunUBT.bat` on Windows).
---@param engineDir string?
---@return boolean ok the script exists
---@return string? path built even when the script is missing
function M.ParseUbtPath(engineDir)
    if engineDir == nil then
        return false, nil
    end

    local path = vim.fs.joinpath(engineDir, "Engine", "Build", "BatchFiles", "RunUBT" .. ext)
    return helpers.path.Exists(path), path
end

function M.IsRootEngineDirValid(engineDir)
    local version = M.GetEngineVersion(engineDir)
    return version and version ~= "0.0.0"
end

---Path of the engine's `BuildConfiguration.xml`, whether it exists or not.
---@param engineDir string? engine root folder
---@return string? path nil when there is no engine folder
function M.ParseBuildConfiguration(engineDir)
    if engineDir == nil then
        return nil
    end

    return vim.fs.joinpath(engineDir, "Engine", "Saved", "UnrealBuildTool", "BuildConfiguration.xml")
end

---@param callback fun(path: string?)
function M.InputEnginePath(callback)
    require("unreal.ui").Input({ prompt = "Enter Unreal Engine path: ", completion = "dir" }, function(input)
        if input == nil or input == "" then
            callback(nil)
        else
            callback(input)
        end
    end)
end

-----------------------------------
local engineExecutable = {
    Win64 = "UnrealEditor.exe",
    Linux = "UnrealEditor",
    Mac = "UnrealEditor.app",
}

---@return boolean
---@return string?
function M.GetEngineExecutable(engineDir)
    if engineDir == nil then
        return false, nil
    end

    local binariesPath = vim.fs.joinpath(engineDir, "Engine", "Binaries")

    local exeName = engineExecutable[platform]
    local exePath = vim.fs.joinpath(binariesPath, platform, exeName)
    local exists = helpers.path.Exists(exePath)

    return exists, exePath
end

---The command that starts Unreal Editor in the background; add the `.uproject` path at the end.
---Starts the engine's `UnrealEditor` directly, detached so it keeps running
---if Neovim closes.
---@param engineDir string
---@return boolean ok whether the editor program exists
---@return string[] cmd command and arguments, without the `.uproject` path
function M.GetExecuteCmd(engineDir)
    local exists, executablePath = M.GetEngineExecutable(engineDir)

    if platform == "Win64" then
        return exists, { executablePath }
    elseif platform == "Linux" then
        if vim.fn.executable("systemd-run") == 1 then
            return exists, { "systemd-run", "--user", "--collect", "--quiet", "--", executablePath }
        else
            return exists, { "setsid", "-f", executablePath }
        end
    elseif platform == "Mac" then
        return exists, { "open", "-n", "-a", executablePath, "--args" }
    end

    return false, {}
end

---The engine's version, e.g. `"5.4.2"`, read from `Engine/Build/Build.version`.
---@param engineDir string? engine root folder
---@return string version `"0.0.0"` when there is no engine path, or the file is missing or unreadable
function M.GetEngineVersion(engineDir)
    local default = "0.0.0"

    if not engineDir then
        return default
    end

    local versionFile = vim.fs.joinpath(engineDir, "Engine", "Build", "Build.version")
    if not helpers.path.Exists(versionFile) then
        return default
    end

    local file = io.open(versionFile, "r")
    if file then
        local content = file:read("*a")
        file:close()

        local ok, jsonData =
            pcall(vim.json.decode, content, { luanil = { object = true, array = true }, skip_comments = true })
        if ok and type(jsonData) == "table" then
            local major = jsonData.MajorVersion or "0"
            local minor = jsonData.MinorVersion or "0"
            local patch = jsonData.PatchVersion or "0"

            return table.concat({ major, minor, patch }, ".")
        end
    end

    return default
end

-----------------------------------

---Which engine folder a project uses, without asking. Order:
---1. the folder from `:Unreal Engine SetPath`;
---2. the installed engine named by the `.uproject`'s `EngineAssociation` field
---   (e.g. `"5.4"`, matching the launcher's `UE_5.4`, or a source build's ID);
---3. the native engine: the engine the working directory is inside, when the `.uproject`'s
---   folder is one of the projects listed through its `.uprojectdirs` files.
---@param uprojectPath string
---@return string? engineDir nil when none of the three applies
---@return ("override"|"associated"|"native")? foundBy which step found it
function M.ResolveEngine(uprojectPath)
    if M.OverrideEnginePath ~= nil then
        return M.OverrideEnginePath, "override"
    end

    uprojectPath = vim.fs.normalize(uprojectPath)

    local installed = M.FindEngine(M.GetAssociatedEngine(uprojectPath))
    if installed then
        return installed.path, "associated"
    end

    if
        M.NativeEngine and helpers.list.StrContains(M.NativeProjects, vim.fs.dirname(uprojectPath), platform == "Linux")
    then
        return M.NativeEngine, "native"
    end

    return nil, nil
end

---How an engine folder got onto this machine:
---- `"native"`: source build that the working directory is inside (see `NativeEngine`);
---- `"launcher"`: installed by the Epic Games Launcher (listed in `LauncherInstalled.dat`);
---- `"cloned"`: source checkout directly inside `engine_source.clone_dir`,
---  e.g. one made by `:Unreal Engine Checkout`;
---- `"source"`: any other source build registered on this machine
---  (`Install.ini` on Linux, the registry on Windows);
---- `nil`: none of the above, e.g. a `:Unreal Engine SetPath` folder nothing knows about.
---@param engineDir string
---@return ("native"|"launcher"|"cloned"|"source")?
function M.GetEngineKind(engineDir)
    local function same(a, b)
        return helpers.list.StrContains({ vim.fs.normalize(a) }, vim.fs.normalize(b), platform == "Linux")
    end

    if M.NativeEngine and same(M.NativeEngine, engineDir) then
        return "native"
    end

    local entry = vim.iter(M.InstalledEngines or {}):find(function(item)
        return same(item.path, engineDir)
    end)
    if entry and entry.kind == "launcher" then
        return "launcher"
    end

    local config = require("unreal.config")
    local cloneDir = (config.opts or config.defaults).engine_source.clone_dir
    if cloneDir and same(cloneDir, vim.fs.dirname(vim.fs.normalize(engineDir))) then
        return "cloned"
    end

    return entry and "source" or nil
end

---Find the engine tools (editor, UnrealBuildTool's `RunUBT` script) for a project and pass them to `callback`.
---Uses the engine from `ResolveEngine`; when there is none, it asks for a folder.
---The typed folder is not remembered.
---`callback(nil)` when the prompt is cancelled or the folder is not a valid engine.
---@param uprojectPath string
---@param callback fun(tools: unreal.EngineTools?)
function M.FindEngineTools(uprojectPath, callback)
    local engineDir = M.ResolveEngine(uprojectPath)
    if engineDir then
        callback(M.RetrieveTools(engineDir))
        return
    end

    M.InputEnginePath(function(input)
        if input and M.IsRootEngineDirValid(input) then
            callback(M.RetrieveTools(input))
        else
            callback(nil)
        end
    end)
end

function M.GetAssociatedEngine(uprojectPath)
    local file = io.open(uprojectPath, "r")
    if file then
        local content = file:read("*a")
        file:close()

        local ok, data =
            pcall(vim.json.decode, content, { luanil = { object = true, array = true }, skip_comments = true })

        if ok then
            return data.EngineAssociation
        end
    end

    return nil
end

---@private
---@param engineDir string
---@return unreal.EngineTools
function M.RetrieveTools(engineDir)
    local result = {
        RootDir = engineDir,
        Version = M.GetEngineVersion(engineDir),
        BuildConfig = M.ParseBuildConfiguration(engineDir),
    }

    local ubtOk, ubtPath = M.ParseUbtPath(engineDir)
    if ubtOk then
        result.UnrealBuildTool = ubtPath
    end

    local engineOk, engineExe = M.GetExecuteCmd(engineDir)
    if engineOk then
        result.EngineExe = engineExe
    end

    return result
end

return M
