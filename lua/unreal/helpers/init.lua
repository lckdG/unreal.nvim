---@class unreal.Helpers
---@field xml unreal.helpers.Xml
---@field path unreal.helpers.Path
---@field buffer unreal.helpers.Buffer
---@field list unreal.helpers.List
---@field log unreal.helpers.Log
local Helpers = setmetatable({}, {
    __index = function(t, name)
        local mod = require("unreal.helpers." .. name)
        rawset(t, name, mod)
        return mod
    end,
})

return Helpers
