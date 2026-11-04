local M = {}

M.PluginName = ""

---Set the prefix put before every message.
---@param info {PluginName: string}
function M.init(info)
    local pluginName = info.PluginName
    M.PluginName = pluginName .. " "
end

---`vim.notify` with the plugin name prefix.
---@param msg string
---@param level vim.log.levels
function M.Notify(msg, level)
    vim.notify(M.PluginName .. msg, level)
end

return M
