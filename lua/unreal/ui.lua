local M = {}

---@type unreal.UiProvider
M.provider = {}

function M.Use(p)
    M.provider = p or require("unreal.ui.native")
end

function M.Select(...)
    return M.provider.Select(...)
end

function M.Input(...)
    return M.provider.Input(...)
end

function M.FileSearch(...)
    return M.provider.FileSearch(...)
end

function M.GrepSearch(...)
    return M.provider.GrepSearch(...)
end

---
---@param items string[]
---@param indexAsValue boolean?
---@return unreal.UiEntry[]
function M.WrapList(items, indexAsValue)
    local result = {}

    for index, item in ipairs(items) do
        local itemValue = indexAsValue and index or item
        table.insert(result, { name = item, value = itemValue, desc = "" })
    end

    return result
end

-- function M.EntryPicker(completionList, callback)
--     local pickers = require("telescope.pickers")
--     local previewers = require("telescope.previewers")
--     local finders = require("telescope.finders")
--     local actions = require("telescope.actions")
--     local action_state = require("telescope.actions.state")
--     local conf = require("telescope.config").values
--
--     local opts = {}
--     pickers
--         .new(opts, {
--             prompt_title = "Attribute Picker",
--             finder = finders.new_table({
--                 results = completionList,
--                 entry_maker = function(entry)
--                     return {
--                         value = entry.value,
--                         ordinal = entry.name,
--                         display = entry.name,
--                         desc = entry.desc,
--                     }
--                 end,
--             }),
--             sorter = conf.generic_sorter(opts),
--
--             previewer = previewers.new_buffer_previewer({
--                 title = "Description",
--                 define_preview = function(self, entry, status)
--                     vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entry.desc)
--                 end,
--             }),
--
--             attach_mappings = function(prompt_bufnr)
--                 actions.select_default:replace(function()
--                     actions.close(prompt_bufnr)
--
--                     local selection = action_state.get_selected_entry()
--                     callback(selection.value)
--                 end)
--
--                 return true
--             end,
--         })
--         :find()
-- end

return M
