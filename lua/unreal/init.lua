local M = {}

---Entry point for the plugin. Applies config, then registers the `:Unreal` command.
---@param opts ConfigOpts?
function M.setup(opts)
    require('unreal.config').config(opts)

    local configOpts = require('unreal.config').opts
    require('unreal.commands').init(configOpts)
end

return M
