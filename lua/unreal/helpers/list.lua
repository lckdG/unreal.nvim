---@class unreal.helpers.List
local List = {}

List.Contains = vim.list_contains

---@param list string[]
---@param value string
---@param matchCase boolean
---@return boolean
function List.StrContains(list, value, matchCase)
    vim.validate("list", list, "table")
    local function strTransform(v)
        return matchCase and v or string.lower(v)
    end

    for _, v in ipairs(list) do
        if strTransform(v) == strTransform(value) then
            return true
        end
    end

    return false
end

return List
