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
        health.ok("setup(): called")
    else
        health.warn("setup(): not called", "Call require('unreal').setup() in your config")
    end
end

local function check_executable(name, hint)
    local health = vim.health
    if vim.fn.executable(name) == 1 then
        health.ok(name .. ": " .. (get_version(name) or "found"))
    else
        health.error(name .. ": not found", hint)
    end
end

local function check_lsp()
    local health = vim.health
    if vim.lsp.is_enabled("clangd") then
        health.ok("clangd LSP: enabled")
    else
        health.warn("clangd LSP: not enabled", 'Call vim.lsp.enable("clangd")')
    end
end

---@param module string Lua module to require
---@param name string plugin name shown in the report
---@param hint string why the plugin is needed
local function check_plugin(module, name, hint)
    local health = vim.health
    local ok = pcall(require, module)
    if ok then
        health.ok(name .. ": found")
    else
        health.error(name .. ": not found", hint)
    end
end

---Check the folder that `:Unreal Engine Checkout` clones engine source code into and
---`:Unreal Engine Build` builds from (`engine_source.clone_dir`), and that `git` is installed.
---Not set is only info: the option is needed just for those two commands.
---Set but missing on disk is an error, because both commands stop with an error then.
local function check_source_dir()
    local health = vim.health
    local config = require("unreal.config")
    local cloneDir = (config.opts or config.defaults).engine_source.clone_dir

    if cloneDir == nil then
        health.info("clone_dir: not set (only needed by :Unreal Engine Checkout and Build)")
    else
        cloneDir = vim.fs.normalize(cloneDir)
        if require("unreal.path_utils").Exists(cloneDir) then
            health.ok("clone_dir: " .. cloneDir)
        else
            health.error(
                "clone_dir: " .. cloneDir .. " does not exist",
                "Create the folder, or fix engine_source.clone_dir in setup()"
            )
        end
    end

    check_executable("git", "Required by :Unreal Engine Checkout")
end

local function check_project_path()
    local health = vim.health
    local project = require("unreal.project")

    local projectPath = project.UprojectPath
    if projectPath ~= nil then
        health.ok(".uproject: " .. projectPath)
        return true, projectPath
    else
        health.warn(".uproject: none chosen for this session", "Run :Unreal Project Select")
        return false, nil
    end
end

local function check_engine_path(uprojectPath)
    local health = vim.health
    local engine = require("unreal.engine")

    local enginePath = engine.OverrideEnginePath

    if enginePath ~= nil then
        health.warn(
            "Engine: " .. enginePath .. " (from :Unreal Engine SetPath, not the .uproject)",
            "Run :Unreal Engine ClearPath to use the .uproject's engine"
        )
    else
        local engineId = engine.GetAssociatedEngine(uprojectPath)
        local engineInfo = engine.FindEngine(engineId)
        enginePath = engineInfo and engineInfo.path or nil

        if engineInfo then
            health.ok("Engine: " .. engineId .. " at " .. enginePath)
        elseif engineId == nil or engineId == "" then
            health.error(
                "Engine: the .uproject has no EngineAssociation",
                "Open the project once in the Unreal editor, or run :Unreal Engine SetPath"
            )
        else
            health.error(
                "Engine: " .. engineId .. " (EngineAssociation) is not installed",
                "Check EngineAssociation in the .uproject, or run :Unreal Engine SetPath"
            )
        end
    end

    local engineVersion = engine.GetEngineVersion(enginePath)
    if engineVersion ~= "0.0.0" then
        health.ok("Engine version: " .. engineVersion)
    else
        health.warn("Engine version: unknown", "Engine/Build/Build.version is missing or unreadable")
    end

    local exeExists, exePath = engine.GetEngineExecutable(enginePath)
    if exeExists then
        health.ok("Editor: " .. exePath)
    else
        health.warn("Editor: not found", "Needed by :Unreal Project Open; build the editor first")
    end

    local ubtOk, ubtPath = engine.ParseUbtPath(enginePath)
    if ubtOk then
        health.ok("UnrealBuildTool: " .. ubtPath)
    else
        health.warn("UnrealBuildTool: not found", "Needed by :Unreal Build Clangd; is the engine built?")
    end
end

---`:checkhealth unreal`: check everything the plugin needs and explain what is missing:
---programs (`rg`, `clangd`), plugins (plenary.nvim, telescope.nvim when its extension is on),
---whether `setup()` ran, the engine path for the current project, and the engine source
---folder used by `:Unreal Engine Checkout` / `Build`.
function M.check()
    local health = vim.health

    health.start("System dependencies")
    check_executable("rg", "Required by :Unreal Search commands")
    check_executable("clangd", "Required for LSP features")

    health.start("Plugin dependencies")

    local config = require("unreal.config")

    if config.IsExtensionEnabled("telescope") then
        check_plugin("telescope", "telescope.nvim", "Required by the telescope extension")
    end

    check_plugin("plenary", "plenary.nvim", "Required for LSP async calls")
    check_lsp()

    health.start("Project and engine")
    check_setup()

    local isProjectSet, projectPath = check_project_path()
    if isProjectSet then
        check_engine_path(projectPath)
    end

    health.start("Engine source")
    check_source_dir()
end

return M
