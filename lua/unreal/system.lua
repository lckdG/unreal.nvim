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

return M
