local TelescopeUiProvider = {}

---@param opts table
function TelescopeUiProvider.setup(opts)
    local success, _ = pcall(require, "telescope")
    if success == false then
        require("unreal.log").Notify("Telescope is set as Unreal's extension, but the plugin is not enabled or installed", vim.log.levels.ERROR)
        return
    end

    TelescopeUiProvider.AppendIgnorePatterns(opts.ignores)
    require("unreal.ui").Use(TelescopeUiProvider)
end

---@param ignores table?
function TelescopeUiProvider.AppendIgnorePatterns(ignores)
    if ignores == nil then
        return
    end

    local telescopeConfig = require("telescope.config")
    local configValues = telescopeConfig.values
    local telescope_ignore_patterns = configValues.file_ignore_patterns or {}

    local ignore_patterns = vim.deepcopy(telescope_ignore_patterns)
    local extended = false

    for _, pattern in ipairs(ignores) do
        if not vim.tbl_contains(ignore_patterns, pattern) then
            extended = true
            table.insert(ignore_patterns, pattern)
        end
    end

    if extended then
        telescopeConfig.set_defaults({
            file_ignore_patterns = ignore_patterns,
        }, {
            file_ignore_patterns = telescope_ignore_patterns,
        })
    end
end

TelescopeUiProvider.Input = vim.ui.input

---
---@param items unreal.UiEntry[]
---@param opts {prompt?: string}
---@param cb fun(value?: unreal.UiEntry)
function TelescopeUiProvider.Select(items, opts, cb)
    local pickers = require("telescope.pickers")
    local previewers = require("telescope.previewers")
    local finders = require("telescope.finders")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local conf = require("telescope.config").values

    local previewer = items[1] and items[1].desc and previewers.new_buffer_previewer({
        title = "Description",
        define_preview = function(self, entry, status)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entry.desc)
        end,
    }) or nil

    pickers.new({}, {
            prompt_title = opts.prompt,
            finder = finders.new_table({
                results = items,
                entry_maker = function(entry)
                    return {
                        value = entry.value,
                        ordinal = entry.name,
                        display = entry.name,
                        desc = entry.desc,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = previewer,
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    cb(selection)
                end)

                return true
            end,
        })
        :find()
end

---
---@param searchArgs string[]
---@param opts {prompt?: string}
function TelescopeUiProvider.FileSearch(searchArgs, opts)
    require("telescope.builtin").find_files({
        prompt_title = opts.prompt,
        find_command = searchArgs,
    })
end

---
---@param searchArgs string[]
---@param opts {prompt?: string}
function TelescopeUiProvider.GrepSearch(searchArgs, opts)
    local args = vim.list_slice(searchArgs, #searchArgs - 1, #searchArgs)
    require("telescope.builtin").live_grep({
        prompt_title = opts.prompt,
        additional_args = args,
    })
end

return TelescopeUiProvider
