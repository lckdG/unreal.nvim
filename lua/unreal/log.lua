local M = {}

M.PluginName = ""

---
---@param pluginName string
function M.Setup(pluginName)
    M.PluginName = pluginName .. " "
end

---
---@param msg string
---@param level vim.log.levels
function M.Notify(msg, level)
    vim.notify(M.PluginName .. msg, level)
end

return M
