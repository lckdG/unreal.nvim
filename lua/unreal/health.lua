local M = {}

local function get_version(name)
    local output = vim.fn.system(name .. " --version")
    if vim.v.shell_error ~= 0 then
        return nil
    end

    return vim.trim(output:match("[^\r\n]+") or output)
end

local function check_setup()
    local health = vim.health
    if require("unreal").inited then
        health.ok("Plugin is inited")
    else
        health.warn("setup() is not called before running healthcheck")
    end
end

local function check_executable(name, hint)
    local health = vim.health
    if vim.fn.executable(name) == 1 then
        local version = get_version(name)
        if version then
            health.ok(name .. " found (" .. version .. ")")
        else
            health.ok(name .. " found")
        end
    else
        health.error(name .. " not found", hint)
    end
end

local function check_lsp()
    local health = vim.health
    if vim.lsp.is_enabled("clangd") then
        health.ok("nvim clangd is enabled")
    else
        health.warn("nvim clangd is not enabled", 'call vim.lsp.enable("clangd")')
    end
end

---@param module string Lua module to require
---@param name string plugin name shown in the report
---@param hint string why the plugin is needed
local function check_plugin(module, name, hint)
    local health = vim.health
    local ok = pcall(require, module)
    if ok then
        health.ok(name .. " found")
    else
        health.error(name .. " not found", hint)
    end
end

local function check_project_path()
    local health = vim.health
    local project = require("unreal.project")

    local projectPath = project.UprojectPath
    if projectPath ~= nil then
        health.ok(".uproject file set:\n" .. projectPath)
        return true, projectPath
    else
        health.warn("No .uproject set for this session", "Run :Unreal Project Select")
        return false, nil
    end
end

local function check_engine_path(uprojectPath)
    local health = vim.health
    local engine = require("unreal.engine")

    local engineId = engine.GetAssociatedEngine(uprojectPath)
    local engineInfo = engine.FindEngine(engineId)
    local enginePathExist = engineInfo ~= nil
    local enginePath = engineInfo.path

    if enginePathExist then
        health.ok("Associated engine: found\n" .. "ID: " .. engineId .. "\nPath: " .. enginePath)
    else
        health.error("Associated engine: not found", "Check the .uproject file\nOr run :Unreal Engine SetPath")
    end

    local exeExists, exePath = engine.GetEngineExecutable(enginePath)
    if exeExists then
        health.ok("Engine executable:\n" .. exePath)
    else
        health.warn("Engine executable: not found")
    end

    local dotNetBundled, dotnetPath = engine.ParseDotnetPath(enginePath)
    if dotnetPath ~= nil then
        local text = (dotNetBundled and "Bundled .NET found:\n" or "System .NET found:\n") .. dotnetPath
        health.ok(text)
    else
        health.warn(".NET: not found")
    end

    local UbtOk, ubtPath = engine.ParseUbtPath(enginePath)
    if UbtOk then
        health.ok("UnrealBuildTool found:\n" .. ubtPath)
    else
        health.warn("UnrealBuildTool: not found")
    end
end

---`:checkhealth unreal`: check everything the plugin needs and explain what is missing:
---programs (`rg`, `clangd`), plugins (plenary.nvim, telescope.nvim when its extension is on),
---whether `setup()` ran, and the engine path for the current project.
function M.check()
    local health = vim.health

    health.start("System dependencies")
    check_executable("rg", "required for Search commands")
    check_executable("clangd", "for LSP functionalities")

    health.start("Plugin dependencies")

    local config = require("unreal.config")

    if config.IsExtensionEnabled("telescope") then
        check_plugin("telescope", "telescope.nvim", "required by the telescope extension")
    end

    check_plugin("plenary", "plenary.nvim", "required for LSP async calls")
    check_lsp()

    health.start("Plugin core")
    check_setup()

    local isProjectSet, projectPath = check_project_path()
    if isProjectSet then
        check_engine_path(projectPath)
    end
end

return M
