local PathUtils = {}

function PathUtils.Exists(path)
    if path == nil then
        return false
    end
    return vim.uv.fs_stat(path) ~= nil
end

return PathUtils
