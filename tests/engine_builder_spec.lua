local h = dofile("tests/helpers.lua")
h.fake_platform("Linux")
require("unreal.engine")
local config = require("unreal.config")
local system = require("unreal.system")
local builder = require("unreal.engine_builder")

local ERROR = vim.log.levels.ERROR
local URL = "https://github.com/EpicGames/UnrealEngine"

local function ls_remote(code, tags, stderr)
    local lines = {}
    for i, tag in ipairs(tags or {}) do
        table.insert(lines, string.format("%040d\trefs/tags/%s", i, tag))
    end
    local stdout = #lines > 0 and table.concat(lines, "\n") .. "\n" or ""
    return h.spy(vim, "system", function(_, opts, on_exit)
        local cb = type(opts) == "function" and opts or on_exit
        cb({ code = code, stdout = code == 0 and stdout or "", stderr = code == 0 and "" or (stderr or "ERROR") })
        return {}
    end)
end

local function get_tags()
    local result
    system.GetUnrealTags(function(tags)
        result = tags
    end)
    assert.is_true(vim.wait(1000, function()
        return result ~= nil
    end))
    return result
end

local function names(tags)
    return vim.tbl_map(function(t)
        return t.name
    end, tags)
end

local selects

local function use_select(index)
    selects = h.use_select(index)
end

local CLONE_DIR_CASES = {
    ["not set"] = function() end,
    ["missing on disk"] = function(cloneDir)
        return vim.fs.joinpath(cloneDir, "missing")
    end,
}

local function close_window_on_start(action)
    local jobs = 0
    h.stub(vim.fn, "jobstart", function(_, opts)
        jobs = jobs + 1
        vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
        assert.has_no.errors(function()
            opts.on_exit(1, 0, "exit")
        end)
        return 1
    end)
    action()
    assert.are.equal(1, jobs)
end

describe("system.GetUnrealTags", function()
    local notes

    before_each(function()
        config.config()
        notes = h.notifications()
    end)
    after_each(h.reset)

    it("runs git ls-remote --tags --refs on the default git_url", function()
        local calls = ls_remote(0, {})
        get_tags()
        assert.are.same({ "git", "ls-remote", "--tags", "--refs", URL }, calls[1][1])
    end)

    it("custom git_url -> used for ls-remote", function()
        config.config({ engine_source = { git_url = "git@github.com:Me/UnrealEngine.git" } })
        local calls = ls_remote(0, {})
        get_tags()
        assert.are.equal("git@github.com:Me/UnrealEngine.git", calls[1][1][5])
    end)

    it("tags -> sorted newest first, release above preview of the same version", function()
        ls_remote(0, {
            "4.27.2-release",
            "5.4.0-preview-1",
            "5.4.4-release",
            "5.5.0-preview-2",
            "5.4.0-release",
            "5.5.0-preview-10",
        })
        assert.are.same({
            "5.5.0-preview-10",
            "5.5.0-preview-2",
            "5.4.4-release",
            "5.4.0-release",
            "5.4.0-preview-1",
            "4.27.2-release",
        }, names(get_tags()))
    end)

    it("entry name and value -> tag name", function()
        ls_remote(0, { "5.4.4-release" })
        local tag = get_tags()[1]
        assert.are.equal("5.4.4-release", tag.name)
        assert.are.equal("5.4.4-release", tag.value)
    end)

    it("tags that are not X.Y.Z[-suffix] -> skipped", function()
        ls_remote(0, { "UE4", "4.27", "weird", "5.4.4-release" })
        assert.are.same({ "5.4.4-release" }, names(get_tags()))
    end)

    it("no tags -> callback with empty list, no notify", function()
        ls_remote(0, {})
        assert.are.same({}, get_tags())
        assert.are.equal(0, #notes)
    end)

    it("ls-remote fails -> error with stderr, callback not called", function()
        ls_remote(128, nil, "Repository not found")
        local called = false
        system.GetUnrealTags(function()
            called = true
        end)
        assert.is_true(vim.wait(1000, function()
            return #notes > 0
        end))
        assert.is_false(called)
        assert.is_true(h.notified(notes, ERROR, "Repository not found"))
    end)
end)

describe("engine_builder.Checkout", function()
    local cloneDir, notes, tagCalls

    local TAGS = {
        { name = "5.5.0-release", value = "5.5.0-release" },
        { name = "5.4.4-release", value = "5.4.4-release" },
    }

    local function run()
        return h.run_job(builder.Checkout)
    end

    before_each(function()
        cloneDir = h.tmpdir()
        config.config({ engine_source = { clone_dir = cloneDir } })
        notes = h.notifications()
        tagCalls = h.spy(system, "GetUnrealTags", function(cb)
            cb(TAGS)
        end)
    end)
    after_each(h.reset)

    for name, dir in pairs(CLONE_DIR_CASES) do
        it("clone_dir " .. name .. " -> error, tags not listed, no clone", function()
            config.config({ engine_source = { clone_dir = dir(cloneDir) } })
            use_select(1)
            local state = run()
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
            assert.are.equal(0, #tagCalls)
            assert.are.equal(0, #selects)
            assert.are.equal(0, #state.calls)
        end)
    end

    it("lists the tags in the order GetUnrealTags returns", function()
        use_select(nil)
        run()
        assert.are.equal(1, #selects)
        assert.are.same(TAGS, selects[1].items)
    end)

    it("select dismissed -> no clone, no split", function()
        use_select(nil)
        local wins = #vim.api.nvim_list_wins()
        local state = run()
        assert.are.equal(0, #state.calls)
        assert.are.equal(wins, #vim.api.nvim_list_wins())
    end)

    it("tag chosen -> shallow clone of that tag into clone_dir/<tag>", function()
        use_select(2)
        local state = run()
        assert.are.equal(1, #state.calls)
        assert.are.same({
            "git",
            "clone",
            "--depth",
            "1",
            "--branch",
            "5.4.4-release",
            URL,
            vim.fs.joinpath(cloneDir, "5.4.4-release"),
        }, state.calls[1].cmd)
    end)

    it("target folder exists -> warning, no clone, no split", function()
        vim.fn.mkdir(vim.fs.joinpath(cloneDir, "5.4.4-release"), "p")
        use_select(2)
        local wins = #vim.api.nvim_list_wins()
        local state = run()
        assert.is_true(h.notified(notes, vim.log.levels.WARN, "5.4.4-release"))
        assert.are.equal(0, #state.calls)
        assert.are.equal(wins, #vim.api.nvim_list_wins())
    end)

    it("custom git_url -> cloned from it", function()
        config.config({ engine_source = { git_url = "git@github.com:Me/UnrealEngine.git", clone_dir = cloneDir } })
        use_select(1)
        local state = run()
        assert.are.equal("git@github.com:Me/UnrealEngine.git", state.calls[1].cmd[7])
    end)

    it("clone_dir with spaces -> target stays one argument", function()
        local spaced = vim.fs.joinpath(h.tmpdir(), "Unreal Engines")
        vim.fn.mkdir(spaced, "p")
        config.config({ engine_source = { clone_dir = spaced } })
        use_select(1)
        local state = run()
        assert.are.equal(vim.fs.joinpath(spaced, "5.5.0-release"), state.calls[1].cmd[8])
    end)

    it("runs in a terminal split and focuses it after exit", function()
        use_select(1)
        local before = vim.api.nvim_get_current_win()
        local state = run()
        assert.is_true(state.calls[1].opts.term)
        assert.are_not.equal(before, state.calls[1].win)
        assert.are.equal(state.calls[1].win, vim.api.nvim_get_current_win())
        assert.is_nil(state.callback_error)
    end)

    it("terminal window closed before exit -> no error", function()
        use_select(1)
        close_window_on_start(builder.Checkout)
    end)
end)

describe("engine_builder.Build", function()
    local cloneDir, confirms, notes, initCalls

    local SCRIPTS = {
        Linux = { "Setup.sh", "GenerateProjectFiles.sh", "Engine/Build/BatchFiles/Linux/Build.sh" },
        Mac = { "Setup.sh", "GenerateProjectFiles.sh", "Engine/Build/BatchFiles/Mac/Build.sh" },
        Win64 = { "Setup.bat", "GenerateProjectFiles.bat", "Engine/Build/BatchFiles/Build.bat" },
    }

    local function checkout(name, platform, root)
        local dir = vim.fs.joinpath(root or cloneDir, name)
        vim.fn.mkdir(dir, "p")
        for _, rel in ipairs(SCRIPTS[platform or "Linux"]) do
            h.write(dir, rel)
        end
        return dir
    end

    local function use_confirm(answer)
        confirms = h.spy(vim.fn, "confirm", answer)
    end

    local function run(code)
        return h.run_job(builder.Build, code)
    end

    local function expected_cmd(dir, platform)
        local q = vim.fn.shellescape
        local s = SCRIPTS[platform]
        return table.concat({
            q(vim.fs.joinpath(dir, s[1])),
            "&&",
            q(vim.fs.joinpath(dir, s[2])),
            "&&",
            q(vim.fs.joinpath(dir, s[3])),
            "UnrealEditor",
            platform,
            "Development",
            "-WaitMutex",
        }, " ")
    end

    before_each(function()
        cloneDir = h.tmpdir()
        config.config({ engine_source = { clone_dir = cloneDir } })
        notes = h.notifications()
        h.fake_platform("Linux")
        initCalls = h.spy(require("unreal.engine"), "init")
        use_confirm(1)
    end)
    after_each(h.reset)

    for name, dir in pairs(CLONE_DIR_CASES) do
        it("clone_dir " .. name .. " -> error, no picker, no build", function()
            config.config({ engine_source = { clone_dir = dir(cloneDir) } })
            use_select(1)
            local state = run()
            assert.is_true(h.notified(notes, ERROR))
            assert.are.equal(0, #selects)
            assert.are.equal(0, #state.calls)
        end)
    end

    it("no checkout in clone_dir -> warning, no picker, no build", function()
        use_select(1)
        local state = run()
        assert.is_true(h.notified(notes, vim.log.levels.WARN, "Engine Checkout"))
        assert.are.equal(0, #selects)
        assert.are.equal(0, #state.calls)
    end)

    it("lists only folders that have all three scripts", function()
        local a = checkout("5.4.4-release")
        local b = checkout("5.5.0-release")
        local partial = vim.fs.joinpath(cloneDir, "partial")
        h.write(partial, "Setup.sh")
        h.write(partial, "GenerateProjectFiles.sh")
        h.write(cloneDir, "notes.txt")
        checkout("windows-only", "Win64")
        use_select(nil)
        run()
        assert.are.equal(1, #selects)
        local values = vim.tbl_map(function(item)
            return item.value
        end, selects[1].items)
        table.sort(values)
        assert.are.same({ a, b }, values)
    end)

    it("picker dismissed -> no confirm, no build, no split", function()
        checkout("5.4.4-release")
        use_select(nil)
        local wins = #vim.api.nvim_list_wins()
        local state = run()
        assert.are.equal(0, #confirms)
        assert.are.equal(0, #state.calls)
        assert.are.equal(wins, #vim.api.nvim_list_wins())
    end)

    for _, answer in ipairs({ 2, 0 }) do
        it("confirm answer " .. answer .. " -> no build, no split", function()
            checkout("5.4.4-release")
            use_select(1)
            use_confirm(answer)
            local wins = #vim.api.nvim_list_wins()
            local state = run()
            assert.are.equal(1, #confirms)
            assert.are.equal(0, #state.calls)
            assert.are.equal(wins, #vim.api.nvim_list_wins())
        end)
    end

    it("confirm defaults to No", function()
        checkout("5.4.4-release")
        use_select(1)
        run()
        assert.are.equal(2, confirms[1][3])
    end)

    for _, platform in ipairs({ "Linux", "Mac", "Win64" }) do
        it(platform .. " -> Setup && GenerateProjectFiles && Build UnrealEditor, run from the checkout", function()
            h.fake_platform(platform)
            local dir = checkout("5.4.4-release", platform)
            use_select(1)
            local state = run()
            assert.are.equal(1, #state.calls)
            assert.are.equal(expected_cmd(dir, platform), state.calls[1].cmd)
            assert.are.equal(dir, state.calls[1].opts.cwd)
        end)
    end

    it("clone_dir with spaces -> script paths quoted", function()
        local spaced = vim.fs.joinpath(h.tmpdir(), "Unreal Engines")
        vim.fn.mkdir(spaced, "p")
        config.config({ engine_source = { clone_dir = spaced } })
        local dir = checkout("5.4.4-release", "Linux", spaced)
        use_select(1)
        local state = run()
        assert.are.equal(expected_cmd(dir, "Linux"), state.calls[1].cmd)
    end)

    it("runs in a terminal split and focuses it after exit", function()
        checkout("5.4.4-release")
        use_select(1)
        local before = vim.api.nvim_get_current_win()
        local state = run()
        assert.is_true(state.calls[1].opts.term)
        assert.are_not.equal(before, state.calls[1].win)
        assert.are.equal(state.calls[1].win, vim.api.nvim_get_current_win())
        assert.is_nil(state.callback_error)
    end)

    it("exit 0 -> engine.init rerun, no error", function()
        checkout("5.4.4-release")
        use_select(1)
        run(0)
        assert.are.equal(1, #initCalls)
        assert.is_false(h.notified(notes, ERROR))
    end)

    it("exit non-zero -> error with exit code, engine.init not rerun", function()
        checkout("5.4.4-release")
        use_select(1)
        run(3)
        assert.is_true(h.notified(notes, ERROR, "(3)"))
        assert.are.equal(0, #initCalls)
    end)

    describe("project engine and SetPath folder", function()
        local engine, project

        local function launcher_engine(dir)
            dir = dir or h.tmpdir()
            h.write_version(dir)
            return dir
        end

        local function source_engine()
            return launcher_engine(checkout("engine", "Linux", h.tmpdir()))
        end

        local function use_uproject()
            project.UprojectPath = h.write_uproject(h.tmpdir(), "5.4")
        end

        local function use_project_engine(dir)
            h.stub(engine, "InstalledEngines", { { id = "UE_5.4", path = dir } })
            use_uproject()
        end

        local function listed()
            use_select(nil)
            run()
            return selects[1] and selects[1].items or {}
        end

        before_each(function()
            engine = require("unreal.engine")
            project = require("unreal.project")
            h.stub(engine, "InstalledEngines", {})
            h.stub(engine, "OverrideEnginePath", nil)
            h.stub(project, "UprojectPath", nil)
        end)

        it("source-built project engine -> first entry, labelled with its version, checkouts after", function()
            local dir = source_engine()
            use_project_engine(dir)
            local co = checkout("5.5.0-release")
            local items = listed()
            assert.are.equal(2, #items)
            assert.are.equal(dir, items[1].value)
            assert.is_truthy(items[1].name:find("^Project Engine"))
            assert.is_truthy(items[1].name:find("(5.4.2)", 1, true))
            assert.are.same({ name = "5.5.0-release", value = co }, items[2])
        end)

        it("launcher project engine -> not listed", function()
            use_project_engine(launcher_engine())
            checkout("5.5.0-release")
            local items = listed()
            assert.are.equal(1, #items)
            assert.are.equal("5.5.0-release", items[1].name)
        end)

        it("EngineAssociation not installed -> not listed, no error", function()
            use_uproject()
            checkout("5.5.0-release")
            local items = listed()
            assert.are.equal(1, #items)
            assert.is_false(h.notified(notes, ERROR))
        end)

        it("source-built SetPath folder -> listed after the project engine, labelled with its version", function()
            local projectDir = source_engine()
            use_project_engine(projectDir)
            local overrideDir = source_engine()
            engine.OverrideEnginePath = overrideDir
            local items = listed()
            assert.are.equal(2, #items)
            assert.are.equal(projectDir, items[1].value)
            assert.are.equal(overrideDir, items[2].value)
            assert.is_truthy(items[2].name:find("^Overridden Engine"))
            assert.is_truthy(items[2].name:find("(5.4.2)", 1, true))
        end)

        it("launcher SetPath folder -> not listed", function()
            engine.OverrideEnginePath = launcher_engine()
            checkout("5.5.0-release")
            local items = listed()
            assert.are.equal(1, #items)
            assert.are.equal("5.5.0-release", items[1].name)
        end)

        it("SetPath folder is the project engine -> listed twice", function()
            local dir = source_engine()
            use_project_engine(dir)
            engine.OverrideEnginePath = dir
            local items = listed()
            assert.are.equal(2, #items)
            assert.are.equal(dir, items[1].value)
            assert.are.equal(dir, items[2].value)
        end)

        it("clone_dir not set -> project engine still offered", function()
            config.config({ engine_source = { clone_dir = nil } })
            local dir = source_engine()
            use_project_engine(dir)
            local items = listed()
            assert.are.equal(1, #items)
            assert.are.equal(dir, items[1].value)
        end)

        it("project engine picked -> built from its folder", function()
            local dir = source_engine()
            use_project_engine(dir)
            use_select(1)
            local state = run()
            assert.are.equal(1, #state.calls)
            assert.are.equal(expected_cmd(dir, "Linux"), state.calls[1].cmd)
            assert.are.equal(dir, state.calls[1].opts.cwd)
        end)
    end)

    it("terminal window closed before exit -> no error", function()
        checkout("5.4.4-release")
        use_select(1)
        close_window_on_start(builder.Build)
    end)
end)
