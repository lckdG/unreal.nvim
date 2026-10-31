local M = {}

---Prompt an option panel for user to select.
---Inputs are numbers from 1-n for a n-options panel
---@param prompt string
---@param options table
---@return number
function M.SelectOptions(prompt, options)
    for index, opt in ipairs(options) do
        prompt = prompt .. tostring(index) .. ": " .. opt .. "\n"
    end

    return vim.fn.inputlist(prompt)
end

---Prompt an option panel for user to select.
---Inputs are numbers from 1-n for a n-options panel
---This option also trigger a callback
---@param prompt string
---@param options table
---@param callback function
function M.SelectOptionsCb(prompt, options, callback)
    local index = M.SelectOptions(prompt, options)
    if index == nil or index <= 0 or index > #options then
        return
    end

    callback(options[index])
end

return M
