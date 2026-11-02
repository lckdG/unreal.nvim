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

local function check_engine_path()
    local health = vim.health
    local engine = require("unreal.engine")

    engine.initDefaults()

    local enginePath = engine.ReadEnginePath()
    local ubtPathValid = enginePath ~= nil and engine.IsUbtExist(enginePath) or false

    local platform = require("unreal.system").GetPlatform()
    local executablePath = enginePath ~= nil and engine.GetEngineExecutable(platform, enginePath) or nil
    local executablePathValid = require("unreal.path_utils").Exists(executablePath)

    if ubtPathValid and executablePathValid then
        health.ok("All required paths found")
    else
        health.error("Required path(s) missing")
    end

    if enginePath ~= nil then
        health.ok("Engine path found: " .. enginePath)
    else
        health.warn("Engine path not set", "Run :Unreal SetEnginePath")
    end

    if executablePathValid then
        health.ok("Executable path found:\n" .. executablePath)
    else
        health.warn("Executable path not found")
    end

    if ubtPathValid then
        health.ok("UBT path found:\n" .. engine.ParseUbtPath(enginePath))
    else
        health.warn("UBT path not found")
    end
end

---Run `:checkhealth unreal` diagnostics: dependencies (with version if found)
---and whether an engine path is resolved for the current project.
function M.check()
    local health = vim.health

    health.start("System dependencies")
    check_executable("rg", "telescope.nvim dependency")
    check_executable("dotnet", "for Unreal tools, e.g. UBT, UHT,...")
    check_executable("clangd", "for LSP functionalities")

    health.start("Plugin dependencies")
    check_plugin("telescope", "telescope.nvim", "required for search commands")
    check_plugin("plenary", "plenary.nvim", "required for CompleteMacro")

    health.start("Plugin core")
    check_setup()
    check_engine_path()
end

return M
