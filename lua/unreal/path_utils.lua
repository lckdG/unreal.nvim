local M = {}

function M.ToIgnoreDirPattern(name)
    local slash = package.config:sub(1, 1)
    return "%f[^" .. slash .. "%z]" .. name .. slash
end

function M.Exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

---Find uproject files in current directory
---@param opts UprojectFindOpts
---@return table
function M.FindUprojects(opts)
    if opts == nil then
        opts = {
            upward = false,
            nameOnly = false,
        }
    end

    local files = vim.fs.find(function(name, _)
        return name:match('.*%.uproject')
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
    local info = require('unreal.config').info
    local desiredExt = extension == info.CppExt and info.HeaderExt or info.CppExt

    local fileName = vim.fn.expand("%:t:r")
    local directory = M.GetSourceFilesRoot()
    if directory == nil then return nil end

    local switchingFiles = vim.fs.find(function (name, _)
        return name == fileName .. "." .. desiredExt
    end, { limit = 1, type = "file", path = directory })

    return #switchingFiles > 0 and switchingFiles[1] or nil
end

return M
