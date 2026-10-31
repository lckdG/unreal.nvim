local M = {}

---Prompt an option panel for user to select.
---Inputs are numbers from 1-n for a n-options panel
---@param prompt string
---@param options table
---@param callback function
function M.SelectOptions(prompt, options, callback)
    for index, file in ipairs(options) do
        prompt = prompt .. tostring(index) .. ": " .. file .. "\n"
    end

    vim.ui.input({ prompt = prompt }, function (input)
        if input == nil or input == "" then
            return
        end

        local chosen = tonumber(input)
        callback(options[chosen])
    end)
end

return M
