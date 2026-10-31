local M = {}

M.PluginName = ""

---
---@param info table
function M.init(info)
    local pluginName = info.PluginName
    M.PluginName = pluginName .. " "
end

---
---@param msg string
---@param level vim.log.levels
function M.Notify(msg, level)
    vim.notify(M.PluginName .. msg, level)
end

return M
