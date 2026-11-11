return setmetatable({}, {
    __index = function (t, name)
        local mod = require("unreal.helpers." .. name)
        rawset(t, name, mod)
        return mod
    end,
})
