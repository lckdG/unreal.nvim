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
    command_lead = "Unreal",
    clangd_build_args = {
        "-NoExecCodeGenActions",
    },
    cmd_abbreviations = {},
    extensions = {},
}

function M.config(opts)
    M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})

    -- TODO: remove
    if M.opts.telescope_extended_ignores ~= nil then
        vim.deprecate(
            "telescope_extended_ignores",
            "extensions = { telescope = { ignores = ... } }",
            "0.3.0",
            M.info.PluginName,
            false
        )

        local telescope = M.opts.extensions.telescope
        if telescope == nil or telescope == true then
            M.opts.extensions.telescope = { ignores = M.opts.telescope_extended_ignores }
        elseif type(telescope) == "table" and telescope.ignores == nil then
            telescope.ignores = M.opts.telescope_extended_ignores
        end
    end
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
