local helpers = require("unreal.helpers")

local Dap = {}

---@param dap any
---@param opts {adapter: string}
local function validateAdapterOpt(dap, opts)
    return opts.adapter ~= nil and dap.adapters[opts.adapter] ~= nil
end

---@param opts {adapter: string}
function Dap.setup(opts)
    local ok, dap = pcall(require, "dap")
    if not ok then
        helpers.log.Notify(
            "nvim-dap is set as Unreal's extension, but the plugin is not enabled or installed",
            vim.log.levels.ERROR
        )
        return
    elseif not validateAdapterOpt(dap, opts) then
        helpers.log.Notify("nvim-dap adapter not configured: " .. tostring(opts.adapter), vim.log.levels.ERROR)
        return
    end
end

return Dap
