local Buffer = {}

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
function Buffer.CreateTemp()
    local tempBufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(tempBufnr, randString(16))

    return tempBufnr
end

function Buffer.OpenBuffer(fileName)
    local buf = vim.fn.bufnr(fileName)
    if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) then
        buf = vim.fn.bufadd(fileName)
        vim.fn.bufload(buf)
    end

    return buf
end

return Buffer
