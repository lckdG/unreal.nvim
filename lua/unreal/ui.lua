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

function M.EntryPicker(completionList, callback)
    local pickers = require('telescope.pickers')
    local previewers = require('telescope.previewers')
    local finders = require('telescope.finders')
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local conf = require('telescope.config').values

    local opts = {}
    pickers.new(opts, {
        prompt_title = "Attribute Picker",
        finder = finders.new_table {
            results = completionList,
            entry_maker = function (entry)
                return {
                    value = entry.name,
                    ordinal = entry.name,
                    display = entry.name,
                    desc = entry.desc,
                }
            end
        },
        sorter = conf.generic_sorter(opts),

        previewer = previewers.new_buffer_previewer({
            title = "Description",
            define_preview = function (self, entry, status)
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entry.desc)
            end,
        }),

        attach_mappings = function (prompt_bufnr)
            actions.select_default:replace(function ()
                actions.close(prompt_bufnr)

                local selection = action_state.get_selected_entry()
                callback(selection.value)
            end)

            return true
        end
    }):find()
end
return M
