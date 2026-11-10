local FsUtils = {}

-- Windows and macOS file systems usually ignore letter case; Linux does not.
local function matchCase()
    return vim.fn.has("linux") == 1 and vim.fn.has("win32") == 0
end

---@param list string[]
---@param value string
---@param caseSensitive boolean
---@return boolean
local function strContains(list, value, caseSensitive)
    vim.validate("list", list, "table")
    local function strTransform(v)
        return caseSensitive and v or string.lower(v)
    end

    for _, v in ipairs(list) do
        if strTransform(v) == strTransform(value) then
            return true
        end
    end

    return false
end

---@param a string
---@param b string
---@return boolean
function FsUtils.PathEquals(a, b)
    return strContains({ vim.fs.normalize(a) }, vim.fs.normalize(b), matchCase())
end

---@param list string[]
---@param path string
---@return boolean
function FsUtils.ContainsPath(list, path)
    return strContains(list, path, matchCase())
end

return FsUtils
