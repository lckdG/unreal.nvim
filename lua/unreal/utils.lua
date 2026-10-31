local M = {}

function M.HasClangdEnabled()
    local clients = vim.lsp.get_clients({ name = "clangd" })
    return #clients > 0
end

function M.IsUnrealProject()
    local uprojectFiles = M.FindUprojects { nameOnly = false }
    return #uprojectFiles > 0
end

function M.GetSourceHeader()
    local extension = vim.fn.expand("%:t:e")
    local info = require('unreal.config').info
    local desiredExt = extension == info.CppExt and info.HeaderExt or info.CppExt

    local fileName = vim.fn.expand("%:t:r")
    local directory = M.GetSourceFilesRoot()
    local switchingFiles = vim.fs.find(function (name, _)
        return name:match(fileName .. "%." .. desiredExt)
    end, { limit = 1, type = "file", path = directory })

    return #switchingFiles > 0 and switchingFiles[1] or nil
end

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

    local rootPath = vim.fn.expand("%:.:h")
    while isWanted(getFolderName(rootPath)) == false do
        rootPath = bubbleUp(rootPath)
    end

    -- If this is Public or Private dir, take its root directory
    if isWanted(getFolderName(rootPath)) then
        rootPath = bubbleUp(rootPath)
    end

    return rootPath ~= "." and rootPath or "Source"
end

function M.GetPlatform()
    if vim.fn.has('win32') == 1 then
        return "Win64"
    elseif vim.fn.has('linux') == 1 then
        return "Linux"
    else
        return "Mac"
    end
end

function M.parseBinariesPath(engineRoot)
    return vim.fs.joinpath(
        engineRoot,
        "Engine",
        "Binaries"
    )
end

function M.GetUbtPath(engineRoot)
    local binariesPath = M.parseBinariesPath(engineRoot)
    return vim.fs.joinpath(
        binariesPath,
        "DotNET",
        "UnrealBuildTool",
        "UnrealBuildTool.dll"
    )
end

function M.GetEngineExecutable(engineRoot)
    local binariesPath = M.parseBinariesPath(engineRoot)
    local platform = M.GetPlatform()

    return vim.fs.joinpath(
        binariesPath,
        platform,
        M.getEngineExecutableName(platform)
    )
end

function M.getEngineExecutableName(platform)
    if platform == "Win64" then
        return "UnrealEditor.exe"
    elseif platform == "Linux" then
        return "UnrealEditor"
    else
        return "UnrealEditor.app"
    end
end

function M.GetExecuteCmd(engineRoot)
    local platform = M.GetPlatform()
    if platform == "Win64" then
        return { "cmd", "/c", "start", "" }
    else
        return { M.GetEngineExecutable(engineRoot) }
    end
end

function M.OpenBuffer(fileName)
    local buf = vim.fn.bufnr(fileName)
    if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) then
        buf = vim.fn.bufadd(fileName)
        vim.fn.bufload(buf)
    end

    return buf
end



return M

