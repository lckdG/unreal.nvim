local M = {}

M.info = {
    PluginName = "unreal.nvim",

    CppExt = "cpp",
    HeaderExt = "h",

    CCFile = "compile_commands.json",
}

---@type ConfigOpts
M.defaults = {
    custom_treesitter = {
        url = "https://github.com/taku25/tree-sitter-unreal-cpp",
        revision = "2d2d5c19a9a83e432e43c041252106995614b29a",
    },
    engine_source = {
        git_url = "https://github.com/EpicGames/UnrealEngine",
        clone_dir = nil,
    },
    command_lead = "Unreal",
    uproject_limits = 5,
    clangd_build_args = {
        "-NoExecCodeGenActions",
    },
    cmd_abbreviations = {},
    extensions = {},
}

function M.config(opts)
    M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.GetClangdBuildArgs()
    local args = M.opts.clangd_build_args
    if args == nil then
        return {}
    end

    return args
end

function M.IsExtensionEnabled(name)
    local ext = M.opts and M.opts.extensions[name]
    return ext ~= nil and ext ~= false
end

return M
