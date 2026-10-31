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
end

function M.GetClangdBuildArgs()
    local args = M.opts.clangd_build_args
    if args == nil then return "" end

    return table.concat(args, " ")
end

return M
