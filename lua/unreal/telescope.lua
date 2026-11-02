local M = {}

---@param opts ConfigOpts
function M.init(opts)
    local extended_ignores = opts.telescope_extended_ignores
    M.AppendIgnorePatterns(extended_ignores)
end

---@param extended_ignores table?
function M.AppendIgnorePatterns(extended_ignores)
    local success, _ = pcall(require, "telescope")
    if success == false then
        return
    end

    if extended_ignores == nil then
        return
    end

    local telescopeConfig = require("telescope.config")
    local configValues = telescopeConfig.values
    local telescope_ignore_patterns = configValues.file_ignore_patterns or {}

    local ignore_patterns = vim.deepcopy(telescope_ignore_patterns)
    local extended = false

    for _, pattern in ipairs(extended_ignores) do
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

return M
