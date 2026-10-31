local log = require('unreal.log')
local pathUtils = require('unreal.path_utils')

local M = {}

M.info = {
    PluginName = "unreal.nvim",
    LockFile = "lock.dat",

    CppExt = "cpp",
    HeaderExt = "h",

    CCFile = "compile_commands.json",
}

---@type ConfigOpts
M.defaults = {
    custom_treesitter = {
        url = 'https://github.com/taku25/tree-sitter-unreal-cpp',
        revision = '2d2d5c19a9a83e432e43c041252106995614b29a',
    },
    command_lead = "Unreal",
    cmd_abbreviations = {},
    telescope_extended_ignores = {
        "%.exe", -- Executables
        "%.dll", "%.lib", "%.modules", -- Libraries, modules, etc.
        "%.uasset", "%.umap", "%.pdb", "%.archive", "%.natvis", -- Unreal specific
        "%.po", "%.manifest", -- Localization assets
        "%.uexp", "%.dmp", "%.pb", "%.bin", -- Something I dont really know :)

        -- Generated Directories
        pathUtils.NameToDirectory("Binaries"),
        pathUtils.NameToDirectory("Build"),
        pathUtils.NameToDirectory("DerivedDataCache"),
        pathUtils.NameToDirectory("Intermediate"),
        pathUtils.NameToDirectory("Cooked")
    },
    clangd_build_args = {
        "-NoExecCodeGenActions",
    }
}

function M.config(opts)
    M.opts = vim.tbl_deep_extend('force', M.defaults, opts or {})

    --TODO: move to init.lua
    log.Setup(M.info.PluginName)

    --TODO: move to init.lua
    M.HijackTreesitter()

    --TODO: move to telescope.lua
    M.AppendIgnorePatterns()
end

function M.HijackTreesitter()
    local custom_treesitter_opts = M.opts.custom_treesitter
    if custom_treesitter_opts == nil then return end

    vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = function ()
            require('nvim-treesitter.parsers').cpp = {
                install_info = {
                    url = custom_treesitter_opts.url,
                    revision = custom_treesitter_opts.revision,
                },
                tier = 2
            }
        end
    })
end

function M.AppendIgnorePatterns()
    local success, _ = pcall(require, 'telescope')
    if success == false then
        return
    end

    local telescope_extended_ignores = M.opts.telescope_extended_ignores
    if telescope_extended_ignores == nil then return end

    local telescopeConfig = require('telescope.config')
    local configValues = telescopeConfig.values
    local telescope_ignore_patterns = configValues.file_ignore_patterns or {}

    local ignore_patterns = vim.deepcopy(telescope_ignore_patterns)
    vim.list_extend(ignore_patterns, telescope_extended_ignores)

    telescopeConfig.set_defaults(
        {
            file_ignore_patterns = ignore_patterns
        },
        {
            file_ignore_patterns = telescope_ignore_patterns
        }
    )
end

function M.GetClangdBuildArgs()
    local args = M.opts.clangd_build_args
    if args == nil then return "" end

    return table.concat(args, " ")
end

return M
