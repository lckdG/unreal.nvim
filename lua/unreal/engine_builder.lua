local log = require("unreal.log")
local logLevels = vim.log.levels

local EngineBuilder = {}

---@return string? gitUrl
---@return string? cloneDir
local function getBuilderInfo()
    local config = require("unreal.config")
    local engineSource = config.opts.engine_source
    local cloneDir = vim.fs.normalize(engineSource.clone_dir or "")

    if cloneDir == nil or not require("unreal.path_utils").Exists(cloneDir) then
        log.Notify("Error: Engine source folder not found " .. tostring(cloneDir), logLevels.ERROR)
        return nil, nil
    end

    return engineSource.git_url, cloneDir
end

function EngineBuilder.Checkout()
    local gitUrl, cloneDir = getBuilderInfo()
    if not gitUrl or not cloneDir then
        return
    end

    local system = require("unreal.system")
    system.GetUnrealTags(function(tags)
        require("unreal.ui").Select(tags, { prompt = "Select tag to checkout: " }, function(item)
            if item == nil then
                return
            end

            local tag = item.value
            local dest = vim.fs.joinpath(cloneDir, item.value)

            if require("unreal.path_utils").Exists(dest) then
                log.Notify("Cannot clone to existing directory: " .. dest, logLevels.WARN)
                return
            end

            local command = {
                "git",
                "clone",
                "--depth",
                "1",
                "--branch",
                tag,
                gitUrl,
                vim.fs.joinpath(cloneDir, item.value),
            }

            vim.cmd("botright new")
            local termWin = vim.api.nvim_get_current_win()
            vim.fn.jobstart(command, {
                term = true,
                on_exit = function(_, _)
                    if vim.api.nvim_win_is_valid(termWin) then
                        vim.api.nvim_set_current_win(termWin)
                        vim.cmd("startinsert")
                    end
                end,
            })
        end)
    end)
end

---@param sourceDir string
---@return unreal.EngineSourceScripts
local function getBuildScripts(sourceDir)
    local platform = require("unreal.system").GetPlatform()
    local ext = platform == "Win64" and ".bat" or ".sh"
    local buildDir = vim.fs.joinpath(sourceDir, "Engine", "Build")

    local buildScript
    if platform ~= "Win64" then
        buildScript = vim.fs.joinpath(buildDir, "BatchFiles", platform, "Build.sh")
    else
        buildScript = vim.fs.joinpath(buildDir, "BatchFiles", "Build.bat")
    end

    local setupScript = vim.fs.joinpath(sourceDir, "Setup" .. ext)
    local generateScript = vim.fs.joinpath(sourceDir, "GenerateProjectFiles" .. ext)

    return {
        Setup = setupScript,
        GenerateProjectFile = generateScript,
        Build = buildScript,
    }
end

---Paths of the scripts `:Unreal Engine Build` runs in a source checkout
---(`Setup`, `GenerateProjectFiles`, `Build`), whether they exist or not.
EngineBuilder.GetBuildScripts = getBuildScripts

local function isSourceDirValid(sourceDir)
    local pathUtils = require("unreal.path_utils")

    local scripts = getBuildScripts(sourceDir)
    for _, scriptPath in pairs(scripts) do
        if not pathUtils.Exists(scriptPath) then
            return false
        end
    end

    return true
end

function EngineBuilder.Build()
    local clonedDirs = {}

    for _, source in ipairs({
        { "Project Engine", EngineBuilder.GetProjectEngine },
        { "Overridden Engine", EngineBuilder.GetOverrideEngine },
    }) do
        local dir, version = source[2]()
        if dir ~= nil then
            table.insert(clonedDirs, { name = source[1] .. " (" .. version .. ")", value = dir })
        end
    end

    local _, cloneDir = getBuilderInfo()
    if cloneDir then
        for name, kind in vim.fs.dir(cloneDir) do
            if kind == "directory" then
                local dir = vim.fs.joinpath(cloneDir, name)
                if isSourceDirValid(dir) then
                    table.insert(clonedDirs, { name = vim.fs.basename(dir), value = dir })
                end
            end
        end
    end

    if #clonedDirs == 0 then
        log.Notify("No source directory found, check out first with 'Engine Checkout'", logLevels.WARN)
        return
    end

    local ui = require("unreal.ui")
    ui.Select(clonedDirs, { prompt = "Choose source directory to build: " }, function(item)
        if not item or not item.value then
            return
        end

        local confirm = vim.fn.confirm("Building engine may take a while, do you want to continue?", "Yes\nNo", 2)
        if confirm ~= 1 then
            return
        end

        local dir = item.value
        EngineBuilder.BuildFrom(dir)
    end)
end

function EngineBuilder.GetProjectEngine()
    local uproject = require("unreal.project").UprojectPath
    if not uproject then
        return nil, nil
    end

    local engine = require("unreal.engine")
    local engineDir, _ = engine.ResolveEngine(uproject)

    if engineDir and isSourceDirValid(engineDir) then
        return engineDir, engine.GetEngineVersion(engineDir)
    end

    return nil, nil
end

function EngineBuilder.GetOverrideEngine()
    local engine = require("unreal.engine")

    local overrideEngine = engine.OverrideEnginePath
    if overrideEngine == nil or not isSourceDirValid(overrideEngine) then
        return nil, nil
    end

    return overrideEngine, engine.GetEngineVersion(overrideEngine)
end

function EngineBuilder.BuildFrom(sourceDir)
    local system = require("unreal.system")
    local platform = system.GetPlatform()

    local buildArgs = { platform, "Development", "-WaitMutex" }
    local q = vim.fn.shellescape
    local scripts = getBuildScripts(sourceDir)

    local commands = {
        q(scripts.Setup),
        "&&",
        q(scripts.GenerateProjectFile),
        "&&",
        q(scripts.Build),
        "UnrealEditor",
        table.concat(buildArgs, " "),
    }

    vim.cmd("botright new")
    local termWin = vim.api.nvim_get_current_win()
    vim.fn.jobstart(table.concat(commands, " "), {
        term = true,
        cwd = sourceDir,
        on_exit = function(_, code)
            if vim.api.nvim_win_is_valid(termWin) then
                vim.api.nvim_set_current_win(termWin)
                vim.cmd("startinsert")
            end

            if code ~= 0 then
                log.Notify("Build engine failed (" .. code .. ")", logLevels.ERROR)
            else
                require("unreal.engine").init()
            end
        end,
    })
end

return EngineBuilder
