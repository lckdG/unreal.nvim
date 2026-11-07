local h = dofile("tests/helpers.lua")
local config = require("unreal.config")
local system = require("unreal.system")
local builder = require("unreal.engine_builder")
local ui = require("unreal.ui")

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
    local cloneDir, selects, notes, tagCalls

    local TAGS = {
        { name = "5.5.0-release", value = "5.5.0-release" },
        { name = "5.4.4-release", value = "5.4.4-release" },
    }

    local function use_select(index)
        selects = {}
        ui.Use({
            Select = function(items, opts, cb)
                table.insert(selects, { items = items, opts = opts })
                cb(index and items[index] or nil)
            end,
        })
    end

    local function stub_jobstart()
        local state = { calls = {}, exited = false }
        h.stub(vim.fn, "jobstart", function(cmd, opts)
            table.insert(state.calls, { cmd = cmd, opts = opts, win = vim.api.nvim_get_current_win() })
            vim.schedule(function()
                local ok, err = pcall(opts.on_exit, 1, 0, "exit")
                state.callback_error = not ok and tostring(err) or nil
                state.exited = true
            end)
            return 1
        end)
        return state
    end

    local function run()
        local state = stub_jobstart()
        builder.Checkout()
        if #state.calls > 0 then
            assert.is_true(vim.wait(1000, function()
                return state.exited
            end))
        end
        return state
    end

    before_each(function()
        cloneDir = h.tmpdir()
        config.config({ engine_source = { clone_dir = cloneDir } })
        notes = h.notifications()
        tagCalls = h.spy(system, "GetUnrealTags", function(cb)
            cb(TAGS)
        end)
    end)
    after_each(function()
        ui.Use(nil)
        h.reset()
    end)

    for _, case in ipairs({
        {
            "not set",
            function()
                return nil
            end,
        },
        {
            "missing on disk",
            function()
                return vim.fs.joinpath(cloneDir, "missing")
            end,
        },
    }) do
        it("clone_dir " .. case[1] .. " -> error, tags not listed, no clone", function()
            config.config({ engine_source = { clone_dir = case[2]() } })
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
        local jobs = 0
        h.stub(vim.fn, "jobstart", function(_, opts)
            jobs = jobs + 1
            vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
            assert.has_no.errors(function()
                opts.on_exit(1, 0, "exit")
            end)
            return 1
        end)
        builder.Checkout()
        assert.are.equal(1, jobs)
    end)
end)

describe("engine_builder.Build", function()
    local cloneDir, selects, confirms, notes, initCalls

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

    local function use_select(index)
        selects = {}
        ui.Use({
            Select = function(items, opts, cb)
                table.insert(selects, { items = items, opts = opts })
                cb(index and items[index] or nil)
            end,
        })
    end

    local function use_confirm(answer)
        confirms = h.spy(vim.fn, "confirm", answer)
    end

    local function stub_jobstart(code)
        local state = { calls = {}, exited = false }
        h.stub(vim.fn, "jobstart", function(cmd, opts)
            table.insert(state.calls, { cmd = cmd, opts = opts, win = vim.api.nvim_get_current_win() })
            vim.schedule(function()
                local ok, err = pcall(opts.on_exit, 1, code or 0, "exit")
                state.callback_error = not ok and tostring(err) or nil
                state.exited = true
            end)
            return 1
        end)
        return state
    end

    local function run(code)
        local state = stub_jobstart(code)
        builder.Build()
        if #state.calls > 0 then
            assert.is_true(vim.wait(1000, function()
                return state.exited
            end))
        end
        return state
    end

    local function expected_cmd(dir, platform)
        local q = vim.fn.shellescape
        local s = SCRIPTS[platform]
        local args = platform .. " Development" .. (platform == "Win64" and " -WaitMutex" or "")
        return table.concat({
            q(vim.fs.joinpath(dir, s[1])),
            "&&",
            q(vim.fs.joinpath(dir, s[2])),
            "&&",
            q(vim.fs.joinpath(dir, s[3])),
            "UnrealEditor",
            args,
        }, " ")
    end

    before_each(function()
        cloneDir = h.tmpdir()
        config.config({ engine_source = { clone_dir = cloneDir } })
        notes = h.notifications()
        h.stub(system, "GetPlatform", function()
            return "Linux"
        end)
        initCalls = h.spy(require("unreal.engine"), "init")
        use_confirm(1)
    end)
    after_each(function()
        ui.Use(nil)
        h.reset()
    end)

    for _, case in ipairs({
        {
            "not set",
            function()
                return nil
            end,
        },
        {
            "missing on disk",
            function()
                return vim.fs.joinpath(cloneDir, "missing")
            end,
        },
    }) do
        it("clone_dir " .. case[1] .. " -> error, no picker, no build", function()
            config.config({ engine_source = { clone_dir = case[2]() } })
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
            h.stub(system, "GetPlatform", function()
                return platform
            end)
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

    it("terminal window closed before exit -> no error", function()
        checkout("5.4.4-release")
        use_select(1)
        local jobs = 0
        h.stub(vim.fn, "jobstart", function(_, opts)
            jobs = jobs + 1
            vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
            assert.has_no.errors(function()
                opts.on_exit(1, 0, "exit")
            end)
            return 1
        end)
        builder.Build()
        assert.are.equal(1, jobs)
    end)
end)
