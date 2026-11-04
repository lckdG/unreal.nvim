local config = require("unreal.config")
local pathUtils = require("unreal.path_utils")
local log = require("unreal.log")

local dataRoot = vim.fn.stdpath("data")

--#region Utility functions

local function getProjectRoot()
    local uprojects = pathUtils.FindUprojects({
        upward = true,
        nameOnly = false,
    })

    if #uprojects == 0 then
        return vim.fn.getcwd()
    end
    return vim.fn.fnamemodify(uprojects[1], ":p:h")
end

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
end

---@private
function M.initDefaults()
    M.EnginePathSet = false
    M.EnginePath = nil
    M.WorkingDir = nil
end

---Set (and optionally persist) the Unreal Engine path used to locate UnrealBuildTool.
---@param opts ParseEnginePathOpts
function M.SetEnginePath(opts)
    if M.IsRootEngineDirValid(opts.path) then
        M.EnginePath = opts.path
        M.EnginePathSet = true
        M.WorkingDir = getProjectRoot()

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

---Find dotNET executable, prioritize the bundled files from engine itself
---Then look for dotnet in $PATH
---@param engineDir string?
---@return boolean ok
---@return string? path
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
    table.sort(found)

    local path = found[#found]
    if path and path ~= "" then
        return true, path
    end

    path = vim.fn.exepath("dotnet")
    if path and path ~= "" then
        return false, path
    end

    return false, nil
end

---
---@return boolean ok
---@return string path
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
    lockData[getProjectRoot()] = path

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

    return lockData[getProjectRoot()]
end

function M.InputEnginePath()
    require("unreal.ui").Input({ prompt = "Enter Unreal Engine path: ", completion = "dir" }, function(input)
        if input == nil or input == "" then
            return
        end
        M.SetEnginePath({ path = input, silent = false, savePath = true })
    end)
end

function M.EnsureEnginePath()
    if M.WorkingDir ~= getProjectRoot() then
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
