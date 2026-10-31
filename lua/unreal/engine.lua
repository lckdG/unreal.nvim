local config = require('unreal.config')
local pathUtils = require('unreal.path_utils')
local log = require('unreal.log')

local dataRoot = vim.fn.stdpath('data')

--#region Utility functions

local function getProjectRoot()
    local uprojects = pathUtils.FindUprojects({
        upward = true,
        nameOnly = false,
    })

    if #uprojects == 0 then return vim.fn.getcwd() end
    return vim.fn.fnamemodify(uprojects[1], ":p:h")
end

local function parseUbtPath(engineDir)
    return vim.fs.joinpath(
        engineDir,
        "Engine",
        "Binaries",
        "DotNET",
        "UnrealBuildTool",
        "UnrealBuildTool.dll"
    )
end

local function readLockfile(filePath)
    local file = io.open(filePath, "r")
    if file == nil then return nil end

    local content = file:read('a')
    file:close()

    local ok, data = pcall(vim.json.decode, content)
    if not ok or type(data) ~= "table" then return nil end

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

function M.init()
    local info = config.info

    M.ConfigDir = vim.fs.joinpath(dataRoot, info.PluginName)
    M.LockFilePath = vim.fs.joinpath(M.ConfigDir, info.LockFile)

    if pathUtils.Exists(M.ConfigDir) == false then
        vim.fn.mkdir(M.ConfigDir, "p")
    end

    if pathUtils.Exists(M.LockFilePath) == false then
        local file = io.open(M.LockFilePath, "w")
        if file then
            file:close()
        end
    end

    local enginePath = M.ReadEnginePath()
    if enginePath == nil then
        M.initDefaults()
    else
        M.SetEnginePath { path = enginePath, silent = true, savePath = false }
    end
end

---@private
function M.initDefaults()
    M.EnginePathSet = false
    M.EnginePath = nil
    M.BuildTool = nil
end

---Set (and optionally persist) the Unreal Engine path used to locate UnrealBuildTool.
---@param opts ParseEnginePathOpts
function M.SetEnginePath(opts)
    M.EnginePath = nil
    M.EnginePathSet = false

    if M.parseToolPaths(opts) then
        M.EnginePath = opts.path
        M.EnginePathSet = true

        if opts.savePath then
            M.saveEnginePath(opts.path)
        end
    end
end

---@private
---@param opts ParseEnginePathOpts
---@return boolean
function M.parseToolPaths(opts)
    M.BuildTool = nil

    local path = opts.path
    local silent = opts.silent

    local buildTool = parseUbtPath(path)

    if pathUtils.Exists(buildTool) == false then
        if silent == false then
            log.Notify("Failed to parse tool paths!", vim.log.levels.ERROR)
        end
        return false
    else
        M.BuildTool = buildTool
        return true
    end
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
    if lockData == nil then return nil end

    return lockData[getProjectRoot()]
end


function M.InputEnginePath()
    require('unreal.ui').Input("Enter Unreal Engine path: ", "dir", function (input)
        M.SetEnginePath{ path = input, silent = false, savePath = true }
    end)
end

function M.EnsureEnginePath()
    if M.EnginePathSet == false then
        M.InputEnginePath()
    end

    return M.EnginePathSet
end

-----------------------------------
local engineExecutable = {
    Win64 = "UnrealEditor.exe",
    Linux = "UnrealEditor",
    Mac = "UnrealEditor.app"
}

local function getEngineExecutable(platform)
    local binariesPath = vim.fs.joinpath(
        M.EnginePath,
        "Engine",
        "Binaries"
    )

    local executableName = engineExecutable[platform]
    return vim.fs.joinpath(
        binariesPath,
        platform,
        executableName
    )
end

function M.GetExecuteCmd()
    local platform = require('unreal.system').GetPlatform()
    if platform == "Win64" then
        return { "cmd", "/c", "start", "" }
    else
        return { getEngineExecutable(platform) }
    end
end

return M
