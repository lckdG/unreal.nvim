local M = {}

function M.NameToDirectory(name)
    local slash = package.config:sub(1, 1)
    return name .. slash
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
    local defaultRoot = "Source"
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
        local parentPath = bubbleUp(rootPath)

        if rootPath == parentPath then
            return defaultRoot
        end

        rootPath = parentPath
    end

    return rootPath ~= "." and rootPath or defaultRoot
end

return M
