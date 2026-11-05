local config = require("unreal.config")
local pathUtils = require("unreal.path_utils")
local log = require("unreal.log")

local dataRoot = vim.fn.stdpath("data")

--#region Utility functions

local function readLockfile(filePath)
    if filePath == nil or filePath == "" then
        return nil
    end

    local file = io.open(filePath, "r")
    if file == nil then
        return nil
    end

    local content = file:read("a")
    file:close()

    local ok, data = pcall(vim.json.decode, content)
    if not ok or type(data) ~= "table" then
        return nil
    end

    return data
end

local function writeLockfile(filePath, data)
    if type(data) ~= "table" then
        return false, "Incorrect data format"
    end

    local file = io.open(filePath, "w")
    if file then
        file:write(vim.json.encode(data))
        file:close()

        return true, ""
    end

    return false, "Unable to write to lock file"
end

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

M.ConfigDir = vim.fs.joinpath(dataRoot, config.info.PluginName)
M.LockFilePath = vim.fs.joinpath(M.ConfigDir, config.info.LockFile)

function M.init()
    if pathUtils.Exists(M.ConfigDir) == false then
        vim.fn.mkdir(M.ConfigDir, "p")
    end

    if pathUtils.Exists(M.LockFilePath) == false then
        local file = io.open(M.LockFilePath, "w")
        if file then
            file:close()
        end
    end

    M.initDefaults()

    local enginePath = M.ReadEnginePath()
    if enginePath ~= nil and M.IsRootEngineDirValid(enginePath) then
        M.SetEnginePath({ path = enginePath, silent = true, savePath = false })
    end

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
    local match = vim.iter(M.InstalledEngines):find(function(item)
        return item.id == id
    end)

    return match
end

---@private
function M.initDefaults()
    M.EnginePathSet = false
    M.EnginePath = nil
    M.WorkingDir = nil
end

---Use `opts.path` as the Unreal Engine folder for this project, if it is valid
---(it must contain UnrealBuildTool and a usable dotnet, see `IsRootEngineDirValid`).
---With `savePath = true` it is also remembered for next time.
---An invalid path is ignored; it shows an error unless `silent = true`.
---@param opts ParseEnginePathOpts `{ path, silent?, savePath? }`
function M.SetEnginePath(opts)
    if M.IsRootEngineDirValid(opts.path) then
        M.EnginePath = opts.path
        M.EnginePathSet = true
        M.WorkingDir = pathUtils.GetProjectRoot()

        if opts.savePath then
            M.saveEnginePath(opts.path)
        end
    else
        if opts.silent == false then
            log.Notify("Failed to parse tool paths!", vim.log.levels.ERROR)
        end
    end
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
    if engineDir == nil then
        return false, nil
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
        return false, nil
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

    path = vim.fn.exepath("dotnet")
    if path and path ~= "" then
        return false, path
    end

    return false, nil
end

---Build the `UnrealBuildTool.dll` path inside an engine root.
---@param engineDir string
---@return boolean ok the dll exists
---@return string path built even when the dll is missing
function M.ParseUbtPath(engineDir)
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

---@private
function M.saveEnginePath(path)
    local lockData = readLockfile(M.LockFilePath) or {}
    lockData[pathUtils.GetProjectRoot()] = path

    local success, msg = writeLockfile(M.LockFilePath, lockData)
    if success then
        log.Notify("Engine path updated successfully", vim.log.levels.INFO)
    else
        log.Notify("Save lock file failed: " .. msg, vim.log.levels.ERROR)
    end
end

function M.ReadEnginePath()
    local lockData = readLockfile(M.LockFilePath)
    if lockData == nil then
        return nil
    end

    return lockData[pathUtils.GetProjectRoot()]
end

function M.InputEnginePath()
    require("unreal.ui").Input({ prompt = "Enter Unreal Engine path: ", completion = "dir" }, function(input)
        if input == nil or input == "" then
            return
        end
        M.SetEnginePath({ path = input, silent = false, savePath = true })
    end)
end

---Make sure an engine path is known before a command that needs it.
---If the working directory moved to another project, its saved path is loaded first.
---Still unknown: asks the user. With a prompt that answers later (e.g. from dressing.nvim),
---this returns false before the user types; they run the command again afterwards.
---@return boolean ok true when an engine path is set right now
function M.EnsureEnginePath()
    if M.WorkingDir ~= pathUtils.GetProjectRoot() then
        M.initDefaults()

        local enginePath = M.ReadEnginePath()
        if enginePath ~= nil and M.IsRootEngineDirValid(enginePath) then
            M.SetEnginePath({ path = enginePath, silent = true, savePath = false })
        end
    end

    if M.EnginePathSet == false then
        M.InputEnginePath()
    end

    return M.EnginePathSet
end

-----------------------------------
local engineExecutable = {
    Win64 = "UnrealEditor.exe",
    Linux = "UnrealEditor",
    Mac = "UnrealEditor.app",
}

function M.GetEngineExecutable(platform, enginePath)
    local binariesPath = vim.fs.joinpath(enginePath, "Engine", "Binaries")

    local executableName = engineExecutable[platform]
    return vim.fs.joinpath(binariesPath, platform, executableName)
end

---The command that starts Unreal Editor in the background; add the `.uproject` path at the end.
---Windows opens the file with its default program (normally Unreal Editor).
---Linux and Mac start the engine's `UnrealEditor` directly, detached so it keeps running
---if Neovim closes.
---@return boolean ok whether the editor program exists (always true on Windows)
---@return string[] cmd command and arguments, without the `.uproject` path
function M.GetExecuteCmd()
    local platform = require("unreal.system").GetPlatform()
    local executablePath = M.GetEngineExecutable(platform, M.EnginePath)
    local executableExist = pathUtils.Exists(executablePath)

    if platform == "Win64" then
        -- We can just use cmd to open the project on Windows
        return true, { "cmd", "/c", "start", "" }
    elseif platform == "Linux" then
        if vim.fn.executable("systemd-run") == 1 then
            return executableExist, { "systemd-run", "--user", "--collect", "--quiet", "--", executablePath }
        else
            return executableExist, { "setsid", "-f", executablePath }
        end
    elseif platform == "Mac" then
        return executableExist, { "open", "-n", "-a", executablePath, "--args" }
    end

    return false, {}
end

-----------------------------------

function M.GetUbtDll()
    if M.EnginePathSet == false then
        return nil
    end

    local ok, ubtPath = M.ParseUbtPath(M.EnginePath)
    return ok and ubtPath or nil
end

function M.GetDotNetCmd()
    if M.EnginePathSet == false then
        return nil
    end

    local _, dotnetExe = M.ParseDotnetPath(M.EnginePath)
    return dotnetExe
end

return M
