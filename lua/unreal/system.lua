local log = require("unreal.helpers.log")
local logLevel = vim.log.levels

local M = {}

function M.GetPlatform()
    if vim.fn.has("win32") == 1 then
        return "Win64"
    elseif vim.fn.has("linux") == 1 then
        return "Linux"
    else
        return "Mac"
    end
end

---@param callback fun(tags: any[])
function M.GetUnrealTags(callback)
    local config = require("unreal.config")
    local engine_source = config.opts.engine_source

    vim.system({ "git", "ls-remote", "--tags", "--refs", engine_source.git_url }, function(exitInfo)
        vim.schedule(function()
            if exitInfo.code ~= 0 then
                log.Notify(
                    "Error while listing Unreal Engine tags (" .. exitInfo.code .. "): " .. exitInfo.stderr,
                    logLevel.ERROR
                )
                return
            end

            local tags = {}
            for line in vim.gsplit(exitInfo.stdout, "\n", { trimempty = true }) do
                local name = line:match("\trefs/tags/(.+)$")
                local version = name and vim.version.parse(name, { strict = true })
                if version then
                    table.insert(tags, {
                        name = name,
                        value = name,
                        version = version,
                    })
                end
            end

            table.sort(tags, function(a, b)
                return vim.version.gt(a.version, b.version)
            end)

            callback(tags)
        end)
    end)
end

return M
