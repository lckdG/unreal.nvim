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

return M
