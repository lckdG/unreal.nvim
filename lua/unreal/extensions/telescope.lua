local TelescopeUiProvider = {}

---Turn on the Telescope extension (`extensions = { telescope = true }` or a table of options):
---pickers and searches then use telescope.nvim. Shows an error and keeps the built-in UI
---if telescope.nvim is not installed.
---@param opts {ignores?: string[]}
function TelescopeUiProvider.setup(opts)
    local success, _ = pcall(require, "telescope")
    if success == false then
        require("unreal.log").Notify(
            "Telescope is set as Unreal's extension, but the plugin is not enabled or installed",
            vim.log.levels.ERROR
        )
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

function TelescopeUiProvider.Input(...)
    return vim.ui.input(...)
end

---Telescope picker over `items`; previews `desc` when the first item has one (macro docs).
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

    local previewer = items[1]
            and type(items[1].desc) == "table"
            and previewers.new_buffer_previewer({
                title = "Description",
                define_preview = function(self, entry)
                    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entry.value.desc or {})
                end,
            })
        or nil

    pickers
        .new({}, {
            prompt_title = opts.prompt,
            finder = finders.new_table({
                results = items,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        ordinal = entry.name,
                        display = entry.name,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = previewer,
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    cb(selection and selection.value)
                end)

                return true
            end,
        })
        :find()
end

---`find_files` with the whole rg command as `find_command`.
---@param searchArgs string[] `{ "rg", "--files", <scope args...> }`
---@param opts {prompt?: string}
function TelescopeUiProvider.FileSearch(searchArgs, opts)
    require("telescope.builtin").find_files({
        prompt_title = opts.prompt,
        find_command = searchArgs,
    })
end

---`live_grep` with the scope args as `additional_args`; telescope adds its own rg base args.
---@param searchArgs string[] `{ "rg", "--vimgrep", "-S", <scope args...> }`
---@param opts {prompt?: string}
function TelescopeUiProvider.GrepSearch(searchArgs, opts)
    -- skip the `rg --vimgrep -S` base, telescope supplies its own
    local args = vim.list_slice(searchArgs, 4, #searchArgs)
    require("telescope.builtin").live_grep({
        prompt_title = opts.prompt,
        additional_args = args,
    })
end

return TelescopeUiProvider
