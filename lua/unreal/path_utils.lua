local M = {}

function M.Exists(path)
    if path == nil then
        return false
    end
    return vim.uv.fs_stat(path) ~= nil
end

---The folder that counts as "this project" (used to remember the engine path per project).
---Walks up from the working directory and picks the first folder with a `.uproject`,
---else the first with `.git` or `.p4ignore`, else the working directory itself.
---@return string
function M.GetProjectRoot()
    local cwd = vim.fn.getcwd()
    local function isUproject(name)
        return name:match("%.uproject$") ~= nil
    end

    local root = vim.fs.root(cwd, { isUproject, { ".git", ".p4ignore" } })
    return root or cwd
end

---Find `.uproject` files. `upward = false` searches the whole tree under cwd;
---`upward = true` searches cwd and its parents.
---@param opts UprojectFindOpts?
---@return string[] files full paths, or basenames when `opts.nameOnly`
function M.FindUprojects(opts)
    if opts == nil then
        opts = {
            upward = false,
            nameOnly = false,
        }
    end

    local files = vim.fs.find(function(name, _)
        return vim.fs.ext(name) == "uproject"
    end, {
        upward = opts.upward or false,
        path = opts.upward and vim.fn.getcwd() or nil,
        limit = math.huge,
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

return M
