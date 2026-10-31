local M = {}

function M.NameToDirectory(name)
    local slash = package.config:sub(1, 1)
    return name .. slash
end

function M.Exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

return M
