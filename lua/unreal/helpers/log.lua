---@class unreal.helpers.Log
local Log = {}

Log.LogPrefix = ""

---Set the prefix put before every message.
---@param info {PluginName: string}
function Log.init(info)
    local pluginName = info.PluginName
    Log.LogPrefix = "[" .. pluginName .. "]" .. " "
end

---`vim.notify` with the plugin name prefix.
---@param msg string
---@param level vim.log.levels
function Log.Notify(msg, level)
    vim.notify(Log.LogPrefix .. msg, level)
end

return Log
