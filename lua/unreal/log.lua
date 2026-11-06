local M = {}

M.LogPrefix = ""

---Set the prefix put before every message.
---@param info {PluginName: string}
function M.init(info)
    local pluginName = info.PluginName
    M.LogPrefix = "[" .. pluginName .. "]" .. " "
end

---`vim.notify` with the plugin name prefix.
---@param msg string
---@param level vim.log.levels
function M.Notify(msg, level)
    vim.notify(M.LogPrefix .. msg, level)
end

return M
