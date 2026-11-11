---@class unreal.helpers.Path
local Path = {}

function Path.Exists(path)
    if path == nil then
        return false
    end
    return vim.uv.fs_stat(path) ~= nil
end

return Path
