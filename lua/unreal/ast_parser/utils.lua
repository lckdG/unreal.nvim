local M = {}

function M.GetCursorRow()
    local cursorPos = vim.api.nvim_win_get_cursor(0)
    local row = cursorPos[1] - 1

    return row
end

---
---@param bufnr number
---@param lang string
---@return TSNode? root
function M.GetTreeRoot(bufnr, lang)
    local parser = vim.treesitter.get_parser(bufnr, lang)
    if parser == nil then
        return nil
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    return root
end

---
---@param queryInfo QueryInfo
---@return boolean
function M.IsQueryInfoValid(queryInfo)
    return next(queryInfo) ~= nil
        and queryInfo.bufnr ~= -1
        and queryInfo.cursorRow ~= -1
        and queryInfo.lang ~= nil
        and queryInfo.root ~= nil
end

return M
