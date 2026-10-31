local M = {}

---Entry point for the plugin. Applies config, then registers the `:Unreal` command.
---@param opts ConfigOpts?
function M.setup(opts)
    local config = require('unreal.config')
    config.config(opts)

    local info = config.info
    local configOpts = config.opts

    require('unreal.log').init(info)

    require('unreal.engine').init()
    require('unreal.project').init()
    require('unreal.treesitter').init(configOpts)
    require('unreal.telescope').init(configOpts)

    require('unreal.commands').init(configOpts)
end

return M
