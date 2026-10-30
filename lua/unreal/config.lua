local logs = require('unreal.logs')

local M = {}

M.info = {
    PluginName = "unreal.nvim",
    LockFile = "lock.dat",

    CppExt = "cpp",
    HeaderExt = "h",

    CCFile = "compile_commands.json",
}

local function makeDirectory(name)
    local slash = package.config:sub(1, 1)
    return name .. slash
end

---@type ConfigOpts
M.defaults = {
    custom_treesitter = {
        url = 'https://github.com/taku25/tree-sitter-unreal-cpp',
        revision = '2d2d5c19a9a83e432e43c041252106995614b29a',
    },
    cmd_abbreviations = {},
    telescope_extended_ignores = {
        "%.exe", -- Executables
        "%.dll", "%.lib", "%.modules", -- Libraries, modules, etc.
        "%.uasset", "%.umap", "%.pdb", "%.archive", "%.natvis", -- Unreal specific
        "%.po", "%.manifest", -- Localization assets
        "%.uexp", "%.dmp", "%.pb", "%.bin", -- Something I dont really know :)

        -- Generated Directories
        makeDirectory("Binaries"),
        makeDirectory("Build"),
        makeDirectory("DerivedDataCache"),
        makeDirectory("Intermediate"),
        makeDirectory("Cooked")
    },
    clangd_build_args = {
        "-NoExecCodeGenActions",
    }
}

local dataRoot = vim.fn.stdpath('data')

local function exists(path)
    local handle, err = io.open(path .. "/.", "r")
    if handle then
        io.close(handle)
        return true
    else
        if string.match(tostring(err), "No such file or directory") then
            return false
        else
            return true
        end
    end
end

function M.config(opts, command_lead)
    M.opts = vim.tbl_deep_extend('force', M.defaults, opts or {})

    logs.Setup(M.info.PluginName)

    M.ConfigDir = vim.fs.joinpath(dataRoot, M.info.PluginName)
    M.LockFilePath = vim.fs.joinpath(M.ConfigDir, M.info.LockFile)

    if exists(M.ConfigDir) == false then
        vim.fn.mkdir(M.ConfigDir, "p")
    end

    if exists(M.LockFilePath) == false then
        local file = io.open(M.LockFilePath, "w")
        if file then
            file:close()
        end
    end

    local enginePath = M.ReadEnginePath()
    if enginePath == nil then
        M.InitDefaults()
    else
        M.SetEnginePath { path = enginePath, silent = true, savePath = false }
    end

    M.HijackTreesitter()
    M.AppendIgnorePatterns()
    M.CreateAbbrevs(command_lead)
end

local function getProjectRoot()
    local uprojects = require('unreal.utils').FindUprojects({
        upward = true,
        nameOnly = false,
    })

    if #uprojects == 0 then return vim.fn.getcwd() end
    return vim.fn.fnamemodify(uprojects[1], ":p:h")
end

function M.ReadEnginePath()
    local lockData = require('unreal.utils').ReadLockfile(M.LockFilePath)
    if lockData == nil then return nil end

    return lockData[getProjectRoot()]
end

function M.InitDefaults()
    M.EnginePathSet = false
    M.EnginePath = nil
    M.BuildTool = nil
end

---
---@param opts ParseEnginePathOpts
---@return boolean
function M.ParseToolPaths(opts)
    M.BuildTool = nil

    local path = opts.path
    local silent = opts.silent

    local buildTool = require('unreal.utils').GetUbtPath(path)

    if exists(buildTool) == false then
        if silent == false then
            logs.Notify("Failed to parse tool paths!", vim.log.levels.ERROR)
        end
        return false
    else
        M.BuildTool = buildTool
        return true
    end
end

---Set (and optionally persist) the Unreal Engine path used to locate UnrealBuildTool.
---@param opts ParseEnginePathOpts
function M.SetEnginePath(opts)
    M.EnginePath = nil
    M.EnginePathSet = false

    if M.ParseToolPaths(opts) then
        M.EnginePath = opts.path
        M.EnginePathSet = true

        if opts.savePath then
            M.SaveEnginePath(opts.path)
        end
    end
end

function M.SaveEnginePath(path)
    local utils = require('unreal.utils')

    local lockData = utils.ReadLockfile(M.LockFilePath) or {}
    lockData[getProjectRoot()] = path

    local success, msg = utils.WriteLockfile(M.LockFilePath, lockData)
    if success then
        logs.Notify("Engine path updated successfully", vim.log.levels.INFO)
    else
        logs.Notify("Save lock file failed: " .. msg, vim.log.levels.ERROR)
    end
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

function M.CreateAbbrevs(command_lead)
    local abbrev_config = M.opts.cmd_abbreviations
    if abbrev_config == nil then return end

    local cabbr = vim.cmd.cabbrev

    for key, command in pairs(abbrev_config) do
        cabbr(key, command_lead .. " " .. command)
    end
end

function M.GetClangdBuildArgs()
    local args = M.opts.clangd_build_args
    if args == nil then return "" end

    return table.concat(args, " ")
end

function M.EnsureEnginePath()
    if M.EnginePathSet == false then
        vim.cmd("Unreal SetEnginePath")
    end

    return M.EnginePathSet
end

return M
