local function enableExtensions(extensions)
    for name, extOpts in pairs(extensions) do
        if extOpts ~= false then
            local ok, ext = pcall(require, "unreal.extensions." .. name)
            if not ok then
                require("unreal.log").Notify("Unknown extension: " .. name, vim.log.levels.ERROR)
            else
                ext.setup(extOpts == true and {} or extOpts)
            end
        end
    end
end

local function hookFileTypes()
    vim.filetype.add({
        extension = {
            uproject = "json",
            uplugin = "json",
        },
    })

    local augroup = vim.api.nvim_create_augroup("unreal.nvim.ft", { clear = true })
    vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
        group = augroup,
        pattern = { "*.uproject", "*.uplugin" },
        callback = function()
            vim.bo.shiftwidth = 4
            vim.bo.tabstop = 4
            vim.bo.expandtab = false
        end,
    })
end

local M = {}

M.inited = false

---Start the plugin. Call this once from your config: `require("unreal").setup({ ... })`.
---It merges your options with the defaults, reads which Unreal Engine versions are installed,
---registers the `:Unreal` command (and your abbreviations), turns on extensions,
---and sets up `.uproject`/`.uplugin` file types.
---@param opts ConfigOpts? your options; omitted means all defaults
function M.setup(opts)
    local config = require("unreal.config")
    config.config(opts)

    local info = config.info
    local configOpts = config.opts

    require("unreal.log").init(info)

    require("unreal.engine").init()
    require("unreal.project").init()
    require("unreal.treesitter").init(configOpts)

    require("unreal.commands").init(configOpts)

    enableExtensions(configOpts.extensions)
    hookFileTypes()

    M.inited = true
end

return M
