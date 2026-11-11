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

function M.GetArch()
    local map = {
        x86_64 = "x64",
        aarch64 = "arm64",
        arm64 = "arm64",
    }

    local uname = vim.loop.os_uname()
    return map[uname.machine]
end

function M.OpenBuffer(fileName)
    local buf = vim.fn.bufnr(fileName)
    if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) then
        buf = vim.fn.bufadd(fileName)
        vim.fn.bufload(buf)
    end

    return buf
end

local function randString(length)
    local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = {}

    for i = 1, length do
        local randIndex = math.random(1, #charset)
        table.insert(result, string.sub(charset, randIndex, randIndex))
    end

    return table.concat(result)
end

---@return number tempBufnr
function M.CreateTempBuffer()
    local tempBufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(tempBufnr, randString(16))

    return tempBufnr
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
