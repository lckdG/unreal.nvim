local helpers = require("unreal.helpers")

local M = {}

---The folder that counts as "this project": `.uproject` files are searched under it, and moving
---the working directory to another project folder resets the chosen `.uproject` and engine path.
---Walks up from the working directory and picks the first folder with a `.uproject`,
---else the first with `.git` or `.p4ignore`, else the working directory itself.
---@return string
function M.GetProjectRoot()
    local cwd = vim.fn.getcwd()
    local function isUproject(name)
        return vim.fs.ext(name) == "uproject"
    end

    local root = vim.fs.root(cwd, { isUproject, { ".git", ".p4ignore" } })
    return root or cwd
end

function M.FindNativeEngineRoot()
    local cwd = vim.fn.getcwd()
    local function isUprojectdirs(name)
        return vim.fs.ext(name) == "uprojectdirs"
    end

    return vim.fs.root(
        cwd,
        { isUprojectdirs, { "Setup.bat", "Setup.sh", "GenerateProjectFiles.bat", "GenerateProjectFiles.sh" } }
    )
end

---@param engineRoot string?
function M.GetUprojectdirsFiles(engineRoot)
    if not engineRoot then
        return {}
    end

    local results = {}
    for name, type in vim.fs.dir(engineRoot) do
        if type == "file" and vim.fs.ext(name) == "uprojectdirs" then
            table.insert(results, vim.fs.joinpath(engineRoot, name))
        end
    end

    return results
end

---Find `.uproject` files (Unreal project files) in `opts.path` and all folders below it.
---Without `opts` it searches the project folder (see `GetProjectRoot`).
---Stops after `uproject_limits` files (5 by default), so a huge folder such as your home directory
---does not list everything.
---@param opts UprojectFindOpts?
---@return string[] files full paths, or basenames when `opts.nameOnly`
function M.FindUprojects(opts)
    if opts == nil then
        opts = {
            path = M.GetProjectRoot(),
            nameOnly = false,
        }
    end

    local config = require("unreal.config")
    local files = vim.fs.find(function(name, _)
        return vim.fs.ext(name) == "uproject"
    end, {
        upward = false,
        path = opts.path,
        limit = config.opts.uproject_limits,
        type = "file",
    })

    if opts.nameOnly then
        local result = {}
        for _, file in ipairs(files) do
            table.insert(result, vim.fs.basename(file))
        end

        return result
    end

    return files
end

---The module folder of the current file, where its matching header/source lives.
---Unreal modules usually split code into `Public/` (headers) and `Private/` (sources),
---so from `Source/Game/Private/Foo.cpp` this returns `Source/Game`.
---Without `Public/`/`Private/`, it stops at the folder right under `Source/`.
---@return string? root nil when the file is not inside a `Source/` tree
function M.GetSourceFilesRoot()
    local function isWanted(name)
        return name == "Public" or name == "Private"
    end

    local function getFolderName(path)
        return vim.fn.fnamemodify(path, ":t")
    end

    local function bubbleUp(path)
        return vim.fn.fnamemodify(path, ":h")
    end

    local currentPath = vim.fs.normalize(vim.fn.expand("%:p:h"))
    while true do
        local name = getFolderName(currentPath)
        if isWanted(name) then
            return bubbleUp(currentPath)
        end

        local parentPath = bubbleUp(currentPath)
        if name == "Source" or getFolderName(parentPath) == "Source" then
            return currentPath
        end

        if parentPath == currentPath then
            return nil
        end

        currentPath = parentPath
    end
end

function M.GetSourceHeader()
    local extension = vim.fn.expand("%:t:e")
    local info = require("unreal.config").info
    local desiredExt = extension == info.CppExt and info.HeaderExt or info.CppExt

    local fileName = vim.fn.expand("%:t:r")
    local directory = M.GetSourceFilesRoot()
    if directory == nil then
        return nil
    end

    local switchingFiles = vim.fs.find(function(name, _)
        return name == fileName .. "." .. desiredExt
    end, { limit = 1, type = "file", path = directory })

    return #switchingFiles > 0 and switchingFiles[1] or nil
end

function M.FindEngineInstalledFiles()
    ---@param segments string[]
    ---@return string
    local joinpath = function(segments)
        local slash = package.config:sub(1, 1)
        return table.concat(segments, slash)
    end

    local map = {
        Win64 = {
            {
                path = joinpath({ vim.env.ProgramData or "", "Epic", "UnrealEngineLauncher", "LauncherInstalled.dat" }),
                type = "json",
            },
            {
                path = joinpath({ "HKCU", "Software", "Epic Games", "Unreal Engine", "Builds" }),
                type = "reg",
            },
        },
        Mac = {
            {
                path = joinpath({
                    vim.env.HOME or "",
                    "Library",
                    "Application Support",
                    "Epic",
                    "UnrealEngineLauncher",
                    "LauncherInstalled.dat",
                }),
                type = "json",
            },
        },
        Linux = {
            {
                path = joinpath({ vim.env.HOME or "", ".config", "Epic", "UnrealEngine", "Install.ini" }),
                type = "ini",
            },
        },
    }

    local platform = require("unreal.system").GetPlatform()
    return map[platform]
end

---Path of the project's `BuildConfiguration.xml` (next to the `.uproject`), whether it exists or not.
---@param uprojectFile string full path of the `.uproject`
---@return unreal.UiEntry entry `{ name = "Project Config", value = path }`
function M.GetProjectBuildConfig(uprojectFile)
    local dirName = vim.fs.dirname(uprojectFile)
    return {
        name = "Project Config",
        value = vim.fs.joinpath(dirName, "Saved", "UnrealBuildTool", "BuildConfiguration.xml"),
    }
end

---Paths of your user `BuildConfiguration.xml` files for this OS, whether they exist or not.
---@return unreal.UiEntry[]? entries `{ name, value = path }`; nil on an unknown platform
function M.GetUserBuildConfig()
    local joinpath = vim.fs.joinpath

    local filesMap = {
        Win64 = {
            {
                name = "User AppData Config",
                value = joinpath(vim.env.APPDATA, "Unreal Engine", "UnrealBuildTool", "BuildConfiguration.xml"),
            },
            {
                name = "User Document Config",
                value = joinpath(
                    vim.env.USERPROFILE,
                    "Documents",
                    "Unreal Engine",
                    "UnrealBuildTool",
                    "BuildConfiguration.xml"
                ),
            },
        },
        Linux = {
            {
                name = "User Config",
                value = joinpath(vim.env.HOME, ".config", "Unreal Engine", "UnrealBuildTool", "BuildConfiguration.xml"),
            },
        },
        Mac = {
            {
                name = "User Config",
                value = joinpath(vim.env.HOME, ".config", "Unreal Engine", "UnrealBuildTool", "BuildConfiguration.xml"),
            },
        },
    }

    local platform = require("unreal.system").GetPlatform()
    return filesMap[platform]
end

---@param dir string
---@param fileExt string
---@param depth? number
---@param labelFunc? fun(name: string): string
---@return any[] files
local function FindFiles(dir, fileExt, depth, labelFunc)
    depth = depth or 1
    labelFunc = labelFunc or function(name)
        return name
    end

    local result = {}

    if helpers.path.IsDir(dir) then
        for name, type in vim.fs.dir(dir, { depth = depth }) do
            if type == "file" and vim.fs.ext(name) == fileExt then
                local filePath = vim.fs.joinpath(dir, name)
                local stat = vim.uv.fs_stat(filePath)

                table.insert(result, {
                    name = labelFunc(name),
                    value = filePath,
                    mtime = stat and stat.mtime.sec or 0,
                })
            end
        end

        table.sort(result, function(a, b)
            return a.mtime > b.mtime
        end)
    end

    return result
end

function M.FindLogFiles(projectRoot)
    if projectRoot == nil then
        return {}
    end

    local logDir = vim.fs.joinpath(projectRoot, "Saved", "Logs")
    return FindFiles(logDir, "log")
end

function M.FindCrashLogFiles(projectRoot)
    if projectRoot == nil then
        return {}
    end

    local crashDir = vim.fs.joinpath(projectRoot, "Saved", "Crashes")
    return FindFiles(crashDir, "log", 2, function(name)
        return vim.fs.dirname(name)
    end)
end

function M.FindCrashFiles(projectRoot)
    if projectRoot == nil then
        return {}
    end

    local crashDir = vim.fs.joinpath(projectRoot, "Saved", "Crashes")
    return FindFiles(crashDir, "runtime-xml", 2, function(name)
        return vim.fs.dirname(name)
    end)
end

return M
