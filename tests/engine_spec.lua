local h = dofile("tests/helpers.lua")

local dataHome = h.tmpdir()
vim.env.XDG_DATA_HOME = dataHome

local config = require("unreal.config")
local engine = require("unreal.engine")
local system = require("unreal.system")

local UBT = "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"

local function fake_engine()
    local root = h.tmpdir()
    h.write(root, UBT)
    return root
end

local function fresh_lockfile()
    return h.stub(engine, "LockFilePath", vim.fs.joinpath(h.tmpdir(), "lock.dat"))
end

describe("engine", function()
    local notes

    before_each(function()
        config.config()
        notes = h.notifications()
    end)
    after_each(h.reset)

    describe("before setup()", function()
        it("ReadEnginePath returns nil without error", function()
            h.unload()
            local fresh = require("unreal.engine")
            local ok, res = pcall(fresh.ReadEnginePath)
            h.unload()
            assert.is_true(ok, tostring(res))
            assert.is_nil(res)
        end)

        it("LockFilePath is defined after require, before setup()", function()
            h.unload()
            local path = require("unreal.engine").LockFilePath
            h.unload()
            assert.is_not_nil(path)
        end)
    end)

    describe("init", function()
        it("creates ConfigDir and an empty lock file under stdpath('data')", function()
            h.project({})
            engine.init()
            assert.are.equal(vim.fs.joinpath(dataHome, "nvim", "unreal.nvim"), engine.ConfigDir)
            assert.are.equal(1, vim.fn.isdirectory(engine.ConfigDir))
            assert.are.equal(1, vim.fn.filereadable(engine.LockFilePath))
        end)

        it("no saved path -> defaults", function()
            h.project({})
            engine.init()
            assert.is_false(engine.EnginePathSet)
            assert.is_nil(engine.EnginePath)
            assert.is_nil(engine.BuildTool)
        end)

        it("saved valid path -> set silently", function()
            local root = fake_engine()
            local cwd = h.project({})
            engine.init()
            vim.fn.writefile({ vim.json.encode({ [cwd] = root }) }, engine.LockFilePath)
            notes = h.notifications()
            engine.init()
            assert.is_true(engine.EnginePathSet)
            assert.are.equal(root, engine.EnginePath)
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.BuildTool)
            assert.are.equal(0, #notes)
            vim.fn.writefile({}, engine.LockFilePath)
        end)

        it("saved invalid path after a valid one -> defaults, no notify", function()
            local cwd = h.project({})
            engine.init()
            engine.SetEnginePath({ path = fake_engine(), silent = true, savePath = false })
            vim.fn.writefile({ vim.json.encode({ [cwd] = h.tmpdir() }) }, engine.LockFilePath)
            notes = h.notifications()
            engine.init()
            assert.is_false(engine.EnginePathSet)
            assert.is_nil(engine.EnginePath)
            assert.is_nil(engine.BuildTool)
            assert.are.equal(0, #notes)
            vim.fn.writefile({}, engine.LockFilePath)
        end)
    end)

    describe("lock file", function()
        local cases = {
            { "missing file", nil },
            { "empty file", {} },
            { "invalid JSON", { "{ not json" } },
            { "JSON non-table", { '"x"' } },
        }
        for _, case in ipairs(cases) do
            it(case[1] .. " -> ReadEnginePath nil", function()
                h.project({})
                local lock = fresh_lockfile()
                if case[2] then vim.fn.writefile(case[2], lock) end
                assert.is_nil(engine.ReadEnginePath())
            end)
        end

        it("save then read round-trips", function()
            h.project({})
            fresh_lockfile()
            engine.saveEnginePath("/ue")
            assert.are.equal("/ue", engine.ReadEnginePath())
            assert.is_true(h.notified(notes, "Engine path updated successfully", vim.log.levels.INFO))
        end)

        it("keys by project root; two projects keep separate paths", function()
            fresh_lockfile()
            local a = h.project({ ["A.uproject"] = {}, ["Source/x.txt"] = {} })
            vim.cmd.cd("Source")
            engine.saveEnginePath("/ue-a")
            h.project({})
            engine.saveEnginePath("/ue-b")
            assert.are.equal("/ue-b", engine.ReadEnginePath())
            vim.cmd.cd(vim.fn.fnameescape(a))
            assert.are.equal("/ue-a", engine.ReadEnginePath())
        end)

        it("unwritable lock file -> error notify", function()
            h.project({})
            h.stub(engine, "LockFilePath", h.tmpdir())
            engine.saveEnginePath("/ue")
            assert.is_true(h.notified(notes, "Save lock file failed", vim.log.levels.ERROR))
        end)
    end)

    describe("SetEnginePath", function()
        before_each(function()
            h.project({})
            fresh_lockfile()
            engine.initDefaults()
        end)

        it("valid engine tree -> set, BuildTool points at the dll", function()
            local root = fake_engine()
            engine.SetEnginePath({ path = root, silent = true, savePath = false })
            assert.is_true(engine.EnginePathSet)
            assert.are.equal(root, engine.EnginePath)
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.BuildTool)
        end)

        it("missing dll, silent = false -> error notify", function()
            engine.SetEnginePath({ path = h.tmpdir(), silent = false, savePath = false })
            assert.is_false(engine.EnginePathSet)
            assert.is_true(h.notified(notes, "Failed to parse tool paths!", vim.log.levels.ERROR))
        end)

        it("missing dll, silent = true -> no notify", function()
            engine.SetEnginePath({ path = h.tmpdir(), silent = true, savePath = false })
            assert.is_false(engine.EnginePathSet)
            assert.are.equal(0, #notes)
        end)

        it("savePath = true writes the lock file, false does not", function()
            local root = fake_engine()
            engine.SetEnginePath({ path = root, silent = true, savePath = false })
            assert.is_nil(engine.ReadEnginePath())
            engine.SetEnginePath({ path = root, silent = true, savePath = true })
            assert.are.equal(root, engine.ReadEnginePath())
        end)

        it("invalid path after a valid one keeps the valid state", function()
            local root = fake_engine()
            engine.SetEnginePath({ path = root, silent = true, savePath = false })
            engine.SetEnginePath({ path = h.tmpdir(), silent = true, savePath = false })
            assert.is_true(engine.EnginePathSet)
            assert.are.equal(root, engine.EnginePath)
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.BuildTool)
        end)
    end)

    describe("EnsureEnginePath", function()
        before_each(function()
            h.project({})
            fresh_lockfile()
            engine.initDefaults()
        end)

        it("already set -> true, no prompt", function()
            engine.SetEnginePath({ path = fake_engine(), silent = true, savePath = false })
            local prompts = h.spy(vim.ui, "input")
            assert.is_true(engine.EnsureEnginePath())
            assert.are.equal(0, #prompts)
        end)

        it("sync input with a valid path -> true", function()
            local root = fake_engine()
            local prompts = h.spy(vim.ui, "input", function(_, cb) cb(root) end)
            assert.is_true(engine.EnsureEnginePath())
            assert.are.equal(1, #prompts)
        end)

        it("async input -> false now, true on rerun", function()
            local root = fake_engine()
            local pending
            h.stub(vim.ui, "input", function(_, cb) pending = cb end)
            assert.is_false(engine.EnsureEnginePath())
            pending(root)
            assert.is_true(engine.EnsureEnginePath())
        end)
    end)

    describe("InputEnginePath", function()
        local root

        before_each(function()
            h.project({})
            fresh_lockfile()
            root = fake_engine()
            engine.SetEnginePath({ path = root, silent = true, savePath = false })
        end)

        local function assert_unchanged()
            assert.is_true(engine.EnginePathSet)
            assert.are.equal(root, engine.EnginePath)
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.BuildTool)
        end

        for _, case in ipairs({ { "cancel (nil)", nil }, { "empty string", "" } }) do
            it(case[1] .. " -> no notify, state unchanged", function()
                h.stub(vim.ui, "input", function(_, cb) cb(case[2]) end)
                engine.InputEnginePath()
                assert.are.equal(0, #notes)
                assert_unchanged()
                assert.is_nil(engine.ReadEnginePath())
            end)
        end

        it("invalid path -> error notify, state unchanged, not saved", function()
            local bad = h.tmpdir()
            h.stub(vim.ui, "input", function(_, cb) cb(bad) end)
            engine.InputEnginePath()
            assert.is_true(h.notified(notes, "Failed to parse tool paths!", vim.log.levels.ERROR))
            assert_unchanged()
            assert.is_nil(engine.ReadEnginePath())
        end)

        it("valid path -> set and saved", function()
            local other = fake_engine()
            h.stub(vim.ui, "input", function(_, cb) cb(other) end)
            engine.InputEnginePath()
            assert.are.equal(other, engine.EnginePath)
            assert.are.equal(other, engine.ReadEnginePath())
        end)
    end)

    it("re-resolves the engine path after :cd to another project", function()
        local lock = fresh_lockfile()
        local a, b = fake_engine(), fake_engine()
        local projA = h.project({ ["A.uproject"] = {} })
        local projB = h.project({ ["B.uproject"] = {} })
        vim.fn.writefile({ vim.json.encode({ [projA] = a, [projB] = b }) }, lock)
        vim.cmd.cd(vim.fn.fnameescape(projA))
        engine.SetEnginePath({ path = a, silent = true, savePath = false })
        vim.cmd.cd(vim.fn.fnameescape(projB))
        vim.wait(50)
        engine.EnsureEnginePath()
        assert.are.equal(b, engine.EnginePath)
        assert.are.equal(vim.fs.joinpath(b, UBT), engine.BuildTool)
    end)

    describe("GetExecuteCmd", function()
        local function on(platform)
            h.stub(vim.fn, "has", function(feature)
                return feature == platform and 1 or 0
            end)
            h.stub(engine, "EnginePath", "/ue")
        end

        it("win32 -> Win64, cmd /c start", function()
            on("win32")
            assert.are.equal("Win64", system.GetPlatform())
            assert.are.same({ "cmd", "/c", "start", "" }, engine.GetExecuteCmd())
        end)

        it("linux -> editor binary", function()
            on("linux")
            assert.are.equal("Linux", system.GetPlatform())
            assert.are.same({ "/ue/Engine/Binaries/Linux/UnrealEditor" }, engine.GetExecuteCmd())
        end)

        it("mac -> open -a bundle, or the binary inside it", function()
            on("mac")
            assert.are.equal("Mac", system.GetPlatform())
            local cmd = engine.GetExecuteCmd()
            local bundle = "/ue/Engine/Binaries/Mac/UnrealEditor.app"
            local ok = vim.deep_equal(cmd, { "open", "-a", bundle })
                or vim.deep_equal(cmd, { bundle .. "/Contents/MacOS/UnrealEditor" })
            assert.is_true(ok, vim.inspect(cmd))
        end)
    end)
end)
