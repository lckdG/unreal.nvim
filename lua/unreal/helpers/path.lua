---@class unreal.helpers.Path
local Path = {}

function Path.Exists(path)
    if path == nil then
        return false
    end
    return vim.uv.fs_stat(path) ~= nil
end

function Path.IsDir(path)
    if path == nil then
        return false
    end
    local stat = vim.uv.fs_stat(path)
    return stat ~= nil and stat.type == "directory"
end

return Path
