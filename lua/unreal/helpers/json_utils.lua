local JsonUtils = {}

---@param path string
---@return boolean ok
---@return any data
function JsonUtils.ReadJson(path)
    local file = io.open(path, "r")
    if not file then
        return false, nil
    end

    local content = file:read("*a")
    file:close()

    return pcall(vim.json.decode, content, { luanil = { object = true, array = true }, skip_comments = true })
end

return JsonUtils
