local pathUtils = require("unreal.path_utils")
local log = require("unreal.log")

--#region Utility functions

---@param path string
local function readInstalledJson(path)
    local result = {}

    if pathUtils.Exists(path) then
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

                    table.insert(result, { id = name, path = location })
                end
            end
        end
    end

    return result
end

---@param path string
local function readInstalledIni(path)
    local result = {}

    if pathUtils.Exists(path) then
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
                        table.insert(result, { id = key, path = val })
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
                log.Notify(
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
                        table.insert(result, { id = id, path = location })
                    end
                end
            end

            cb(result)
        end)
    end)
end

--#endregion

local M = {}
M.OverrideEnginePath = nil

function M.init()
    local files = pathUtils.FindEngineInstalledFiles()
    M.FindInstalled(files)
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
---Warns and keeps the old value if the folder has no UnrealBuildTool or usable `dotnet`.
function M.SetEnginePath_User()
    M.InputEnginePath(function(path)
        if path and M.IsRootEngineDirValid(path) then
            M.OverrideEnginePath = path
            log.Notify("Override engine path is set!", vim.log.levels.INFO)
        else
            log.Notify("Input path is invalid, aborting...", vim.log.levels.WARN)
        end
    end)
end

---`:Unreal Engine ClearPath`: forget the folder set with `:Unreal Engine SetPath`,
---so commands go back to the engine the `.uproject` asks for.
function M.ClearEnginePath_User()
    M.OverrideEnginePath = nil
    log.Notify("Override engine path is cleared!", vim.log.levels.INFO)
end

local function parseFromBinaryDir(engineDir, ...)
    return vim.fs.joinpath(engineDir, "Engine", "Binaries", ...)
end

---Find the `dotnet` program used to run UnrealBuildTool (Unreal's build tool, a .NET app).
---Prefers the copy bundled with the engine (`Engine/Binaries/ThirdParty/DotNet/<version>/...`),
---and falls back to `dotnet` installed on your system ($PATH).
---With several bundled versions it takes the newest one, comparing folder names as versions
---(`10.0.100` beats `8.0.300`).
---@param engineDir string? engine root folder
---@return boolean bundled true only when the engine's own copy is used
---@return string? path nil when neither is found
function M.ParseDotnetPath(engineDir)
    local function ParseFromEnv()
        local path = vim.fn.exepath("dotnet")
        if path and path ~= "" then
            return false, path
        else
            return false, nil
        end
    end

    if engineDir == nil then
        return ParseFromEnv()
    end

    local map = {
        Win64 = {
            name = "win",
            fileName = "dotnet.exe",
        },
        Linux = {
            name = "linux",
            fileName = "dotnet",
        },
        Mac = {
            name = "mac",
            fileName = "dotnet",
        },
    }

    local sys = require("unreal.system")
    local platform = sys.GetPlatform()
    local arch = sys.GetArch()

    if arch == nil or map[platform] == nil then
        return ParseFromEnv()
    end

    local dotnetDir = parseFromBinaryDir(engineDir, "ThirdParty", "DotNet")
    local parentDir = map[platform].name .. "-" .. arch
    local globPattern = vim.fs.joinpath(dotnetDir, "*", parentDir, map[platform].fileName)

    local found = vim.fn.glob(globPattern, false, true)
    table.sort(found, function(a, b)
        local function parseVersion(path)
            local archDir = vim.fs.dirname(path)
            local versionDir = vim.fs.dirname(archDir)

            return vim.version.parse(vim.fs.basename(versionDir))
        end

        local va, vb = parseVersion(a), parseVersion(b)
        if va and vb then
            return vim.version.gt(va, vb)
        end

        return a > b
    end)

    local path = found[1]
    if path and path ~= "" then
        return true, path
    end

    return ParseFromEnv()
end

---Build the `UnrealBuildTool.dll` path inside an engine root.
---@param engineDir string?
---@return boolean ok the dll exists
---@return string? path built even when the dll is missing
function M.ParseUbtPath(engineDir)
    if engineDir == nil then
        return false, nil
    end

    local path = vim.fs.joinpath(engineDir, "Engine", "Binaries", "DotNET", "UnrealBuildTool", "UnrealBuildTool.dll")
    return pathUtils.Exists(path), path
end

function M.IsRootEngineDirValid(engineDir)
    local _, dotNetPath = M.ParseDotnetPath(engineDir)
    if dotNetPath == nil then
        return false
    end

    local ok, _ = M.ParseUbtPath(engineDir)
    if not ok then
        return false
    end

    return true
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
function M.GetEngineExecutable(enginePath)
    if enginePath == nil then
        return false, nil
    end

    local platform = require("unreal.system").GetPlatform()
    local binariesPath = vim.fs.joinpath(enginePath, "Engine", "Binaries")

    local exeName = engineExecutable[platform]
    local exePath = vim.fs.joinpath(binariesPath, platform, exeName)
    local exists = pathUtils.Exists(exePath)

    return exists, exePath
end

---The command that starts Unreal Editor in the background; add the `.uproject` path at the end.
---Starts the engine's `UnrealEditor` directly, detached so it keeps running
---if Neovim closes.
---@param enginePath string
---@return boolean ok whether the editor program exists
---@return string[] cmd command and arguments, without the `.uproject` path
function M.GetExecuteCmd(enginePath)
    local platform = require("unreal.system").GetPlatform()
    local exists, executablePath = M.GetEngineExecutable(enginePath)

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
---@param enginePath string? engine root folder
---@return string version `"0.0.0"` when there is no engine path, or the file is missing or unreadable
function M.GetEngineVersion(enginePath)
    local default = "0.0.0"

    if not enginePath then
        return default
    end

    local versionFile = vim.fs.joinpath(enginePath, "Engine", "Build", "Build.version")
    if not pathUtils.Exists(versionFile) then
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

---Find the engine tools (editor, `dotnet`, UnrealBuildTool) for a project and pass them to `callback`.
---Order: the folder from `:Unreal Engine SetPath`; then the installed engine named by the
---`.uproject`'s `EngineAssociation` field (e.g. `"5.4"`, matching the launcher's `UE_5.4`);
---otherwise it asks for a folder. The typed folder is not remembered.
---`callback(nil)` when the prompt is cancelled or the folder is not a valid engine.
---@param uprojectPath string
---@param callback fun(tools: unreal.EngineTools?)
function M.FindEngineTools(uprojectPath, callback)
    if M.OverrideEnginePath ~= nil then
        callback(M.RetrieveTools(M.OverrideEnginePath))
        return
    end

    local engineId = M.GetAssociatedEngine(uprojectPath)
    if engineId ~= nil then
        local engine = M.FindEngine(engineId)
        if engine then
            callback(M.RetrieveTools(engine.path))
            return
        end
    end

    M.InputEnginePath(function(enginePath)
        if M.IsRootEngineDirValid(enginePath) then
            callback(M.RetrieveTools(enginePath))
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
---@param enginePath string
---@return unreal.EngineTools
function M.RetrieveTools(enginePath)
    local result = {
        RootDir = enginePath,
        Version = M.GetEngineVersion(enginePath),
        BuildConfig = M.ParseBuildConfiguration(enginePath),
    }

    local _, dotNetExe = M.ParseDotnetPath(enginePath)
    if dotNetExe ~= nil then
        result.DotNetExe = dotNetExe
    end

    local ubtOk, ubtPath = M.ParseUbtPath(enginePath)
    if ubtOk then
        result.UnrealBuildTool = ubtPath
    end

    local engineOk, engineExe = M.GetExecuteCmd(enginePath)
    if engineOk then
        result.EngineExe = engineExe
    end

    return result
end

return M
