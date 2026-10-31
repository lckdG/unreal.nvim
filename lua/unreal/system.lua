local M = {}

function M.GetPlatform()
    if vim.fn.has('win32') == 1 then
        return "Win64"
    elseif vim.fn.has('linux') == 1 then
        return "Linux"
    else
        return "Mac"
    end
end

function M.HasClangdEnabled()
    local clients = vim.lsp.get_clients{ name = "clangd", bufnr = 0 }
    return #clients > 0
end

function M.OpenBuffer(fileName)
    local buf = vim.fn.bufnr(fileName)
    if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) then
        buf = vim.fn.bufadd(fileName)
        vim.fn.bufload(buf)
    end

    return buf
end

return M
