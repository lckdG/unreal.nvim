local h = dofile("tests/helpers.lua")

local dataHome = h.tmpdir()
vim.env.XDG_DATA_HOME = dataHome

local config = require("unreal.config")
local engine = require("unreal.engine")
local system = require("unreal.system")
local pathUtils = require("unreal.path_utils")

local UBT = "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"
local DOTNET_DIR = "Engine/Binaries/ThirdParty/DotNet"
local hostDotnet = ({ Win64 = "win", Linux = "linux", Mac = "mac" })[system.GetPlatform()] .. "-" .. system.GetArch()
local hostDotnetExe = system.GetPlatform() == "Win64" and "dotnet.exe" or "dotnet"

local function bundled_dotnet(version)
    return vim.fs.joinpath(DOTNET_DIR, version, hostDotnet, hostDotnetExe)
end

local function fake_engine()
    local root = h.tmpdir()
    h.write(root, UBT)
    h.write(root, bundled_dotnet("8.0.300"))
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
        h.stub(vim.fn, "exepath", function()
            return ""
        end)
    end)
    after_each(h.reset)

    describe("before setup()", function()
        it("ReadEnginePath returns nil without error", function()
            h.unload()
            local fresh = require("unreal.engine")
            local ok, res = pcall(fresh.ReadEnginePath)
            h.unload()
            assert.is_true(ok)
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
            assert.is_nil(engine.GetUbtDll())
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
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.GetUbtDll())
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
            assert.is_nil(engine.GetUbtDll())
            assert.are.equal(0, #notes)
            vim.fn.writefile({}, engine.LockFilePath)
        end)

        it("saved path whose UnrealBuildTool.dll was removed -> defaults, no notify", function()
            local root = fake_engine()
            local cwd = h.project({})
            engine.init()
            vim.fn.writefile({ vim.json.encode({ [cwd] = root }) }, engine.LockFilePath)
            vim.fn.delete(vim.fs.joinpath(root, UBT))
            notes = h.notifications()
            engine.init()
            assert.is_false(engine.EnginePathSet)
            assert.is_nil(engine.EnginePath)
            assert.is_nil(engine.GetUbtDll())
            assert.are.equal(0, #notes)
            vim.fn.writefile({}, engine.LockFilePath)
        end)
    end)

    describe("ParseUbtPath", function()
        it("engine dir without UnrealBuildTool.dll -> false, expected path", function()
            local root = h.tmpdir()
            local ok, path = engine.ParseUbtPath(root)
            assert.is_false(ok)
            assert.are.equal(vim.fs.joinpath(root, UBT), path)
        end)

        it("engine dir with UnrealBuildTool.dll -> true, dll path", function()
            local root = fake_engine()
            local ok, path = engine.ParseUbtPath(root)
            assert.is_true(ok)
            assert.are.equal(vim.fs.joinpath(root, UBT), path)
        end)
    end)

    describe("ParseDotnetPath", function()
        local function no_system_dotnet()
            h.stub(vim.fn, "exepath", function()
                return ""
            end)
        end

        it("nil engine dir -> false, nil", function()
            local ok, path = engine.ParseDotnetPath(nil)
            assert.is_false(ok)
            assert.is_nil(path)
        end)

        it("bundled dotnet -> true, bundled path", function()
            no_system_dotnet()
            local root = fake_engine()
            local ok, path = engine.ParseDotnetPath(root)
            assert.is_true(ok)
            assert.are.equal(vim.fs.joinpath(root, bundled_dotnet("8.0.300")), path)
        end)

        it("several bundled versions -> highest sorted one", function()
            local root = fake_engine()
            h.write(root, bundled_dotnet("6.0.302"))
            h.write(root, bundled_dotnet("9.0.100"))
            local _, path = engine.ParseDotnetPath(root)
            assert.are.equal(vim.fs.joinpath(root, bundled_dotnet("9.0.100")), path)
        end)

        it("several bundled versions -> compared as versions, not strings", function()
            local root = fake_engine()
            h.write(root, bundled_dotnet("10.0.100"))
            local _, path = engine.ParseDotnetPath(root)
            assert.are.equal(vim.fs.joinpath(root, bundled_dotnet("10.0.100")), path)
        end)

        it("bundled preferred over system dotnet", function()
            h.stub(vim.fn, "exepath", function()
                return "/usr/bin/dotnet"
            end)
            local root = fake_engine()
            local ok, path = engine.ParseDotnetPath(root)
            assert.is_true(ok)
            assert.are.equal(vim.fs.joinpath(root, bundled_dotnet("8.0.300")), path)
        end)

        it("no bundled, system dotnet -> false, system path", function()
            h.stub(vim.fn, "exepath", function()
                return "/usr/bin/dotnet"
            end)
            local ok, path = engine.ParseDotnetPath(h.tmpdir())
            assert.is_false(ok)
            assert.are.equal("/usr/bin/dotnet", path)
        end)

        it("no bundled, no system dotnet -> false, nil", function()
            no_system_dotnet()
            local ok, path = engine.ParseDotnetPath(h.tmpdir())
            assert.is_false(ok)
            assert.is_nil(path)
        end)

        it("unknown arch -> false, nil", function()
            h.stub(require("unreal.system"), "GetArch", function()
                return nil
            end)
            local ok, path = engine.ParseDotnetPath(fake_engine())
            assert.is_false(ok)
            assert.is_nil(path)
        end)
    end)

    describe("IsRootEngineDirValid", function()
        it("UBT and bundled dotnet -> true", function()
            assert.is_true(engine.IsRootEngineDirValid(fake_engine()))
        end)

        it("UBT, no bundled dotnet, no PATH dotnet -> false", function()
            local root = h.tmpdir()
            h.write(root, UBT)
            assert.is_false(engine.IsRootEngineDirValid(root))
        end)

        it("UBT, no bundled dotnet, PATH dotnet -> true", function()
            h.stub(vim.fn, "exepath", function()
                return "/usr/bin/dotnet"
            end)
            local root = h.tmpdir()
            h.write(root, UBT)
            assert.is_true(engine.IsRootEngineDirValid(root))
        end)

        it("bundled dotnet without UBT -> false", function()
            local root = h.tmpdir()
            h.write(root, bundled_dotnet("8.0.300"))
            assert.is_false(engine.IsRootEngineDirValid(root))
        end)
    end)

    describe("GetUbtDll / GetDotNetCmd", function()
        it("engine path not set -> nil", function()
            engine.initDefaults()
            assert.is_nil(engine.GetUbtDll())
            assert.is_nil(engine.GetDotNetCmd())
        end)

        it("engine path set -> dll and bundled dotnet", function()
            h.project({})
            fresh_lockfile()
            local root = fake_engine()
            engine.SetEnginePath({ path = root, silent = true, savePath = false })
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.GetUbtDll())
            assert.are.equal(vim.fs.joinpath(root, bundled_dotnet("8.0.300")), engine.GetDotNetCmd())
        end)

        for _, case in ipairs({
            { "dotnet on PATH -> PATH dotnet", "/usr/bin/dotnet" },
            { "no PATH dotnet -> nil", "" },
        }) do
            it("bundled dotnet removed after set, " .. case[1], function()
                h.project({})
                fresh_lockfile()
                local root = fake_engine()
                engine.SetEnginePath({ path = root, silent = true, savePath = false })
                vim.fn.delete(vim.fs.joinpath(root, DOTNET_DIR), "rf")
                h.stub(vim.fn, "exepath", function()
                    return case[2]
                end)
                local expected = case[2] ~= "" and case[2] or nil
                assert.are.equal(expected, engine.GetDotNetCmd())
            end)
        end
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
                if case[2] then
                    vim.fn.writefile(case[2], lock)
                end
                assert.is_nil(engine.ReadEnginePath())
            end)
        end

        it("save then read round-trips", function()
            h.project({})
            fresh_lockfile()
            engine.saveEnginePath("/ue")
            assert.are.equal("/ue", engine.ReadEnginePath())
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
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
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
        end)
    end)

    describe("SetEnginePath", function()
        before_each(function()
            h.project({})
            fresh_lockfile()
            engine.initDefaults()
        end)

        it("valid engine tree -> set, GetUbtDll points at the dll", function()
            local root = fake_engine()
            engine.SetEnginePath({ path = root, silent = true, savePath = false })
            assert.is_true(engine.EnginePathSet)
            assert.are.equal(root, engine.EnginePath)
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.GetUbtDll())
        end)

        it("missing dll, silent = false -> error notify", function()
            engine.SetEnginePath({ path = h.tmpdir(), silent = false, savePath = false })
            assert.is_false(engine.EnginePathSet)
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
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
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.GetUbtDll())
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
            local prompts = h.spy(vim.ui, "input", function(_, cb)
                cb(root)
            end)
            assert.is_true(engine.EnsureEnginePath())
            assert.are.equal(1, #prompts)
        end)

        it("async input -> false now, true on rerun", function()
            local root = fake_engine()
            local pending
            h.stub(vim.ui, "input", function(_, cb)
                pending = cb
            end)
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
            assert.are.equal(vim.fs.joinpath(root, UBT), engine.GetUbtDll())
        end

        for _, case in ipairs({ { "cancel (nil)", nil }, { "empty string", "" } }) do
            it(case[1] .. " -> no notify, state unchanged", function()
                h.stub(vim.ui, "input", function(_, cb)
                    cb(case[2])
                end)
                engine.InputEnginePath()
                assert.are.equal(0, #notes)
                assert_unchanged()
                assert.is_nil(engine.ReadEnginePath())
            end)
        end

        it("invalid path -> error notify, state unchanged, not saved", function()
            local bad = h.tmpdir()
            h.stub(vim.ui, "input", function(_, cb)
                cb(bad)
            end)
            engine.InputEnginePath()
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
            assert_unchanged()
            assert.is_nil(engine.ReadEnginePath())
        end)

        it("valid path -> set and saved", function()
            local other = fake_engine()
            h.stub(vim.ui, "input", function(_, cb)
                cb(other)
            end)
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
        assert.are.equal(vim.fs.joinpath(b, UBT), engine.GetUbtDll())
    end)

    for _, case in ipairs({ { "no saved path", false }, { "saved path without UnrealBuildTool.dll", true } }) do
        it(":cd to a project with " .. case[1] .. " -> previous engine dropped, prompt", function()
            local lock = fresh_lockfile()
            local a = fake_engine()
            local projA = h.project({ ["A.uproject"] = {} })
            local projB = h.project({ ["B.uproject"] = {} })
            local saved = { [projA] = a }
            if case[2] then
                saved[projB] = h.tmpdir()
            end
            vim.fn.writefile({ vim.json.encode(saved) }, lock)
            vim.cmd.cd(vim.fn.fnameescape(projA))
            engine.SetEnginePath({ path = a, silent = true, savePath = false })
            vim.cmd.cd(vim.fn.fnameescape(projB))
            local prompts = h.spy(vim.ui, "input")
            assert.is_false(engine.EnsureEnginePath())
            assert.are.equal(1, #prompts)
            assert.is_nil(engine.EnginePath)
            assert.is_nil(engine.GetUbtDll())
        end)
    end

    it(":cd within the same project -> engine kept, no prompt", function()
        local lock = fresh_lockfile()
        local a = fake_engine()
        local proj = h.project({ ["A.uproject"] = {}, ["Source/Mod/x.h"] = {} })
        vim.fn.writefile({ vim.json.encode({ [proj] = a }) }, lock)
        vim.cmd.cd(vim.fn.fnameescape(proj))
        engine.SetEnginePath({ path = a, silent = true, savePath = false })
        vim.cmd.cd(vim.fn.fnameescape(proj .. "/Source/Mod"))
        local prompts = h.spy(vim.ui, "input")
        assert.is_true(engine.EnsureEnginePath())
        assert.are.equal(0, #prompts)
        assert.are.equal(a, engine.EnginePath)
    end)

    describe("GetExecuteCmd", function()
        local function on(platform)
            h.stub(vim.fn, "has", function(feature)
                return feature == platform and 1 or 0
            end)
            h.stub(engine, "EnginePath", "/ue")
            -- host-independent: systemd-run cases opt in via withSystemdRun()
            h.stub(vim.fn, "executable", function()
                return 0
            end)
        end

        local function withSystemdRun()
            h.stub(vim.fn, "executable", function(name)
                return name == "systemd-run" and 1 or 0
            end)
        end

        it("win32 -> Win64, cmd /c start", function()
            on("win32")
            assert.are.equal("Win64", system.GetPlatform())
            local ok, cmd = engine.GetExecuteCmd()
            assert.is_true(ok)
            assert.are.same({ "cmd", "/c", "start", "" }, cmd)
        end)

        it("linux, no systemd-run, editor binary missing -> not ok, setsid", function()
            on("linux")
            assert.are.equal("Linux", system.GetPlatform())
            local ok, cmd = engine.GetExecuteCmd()
            assert.is_false(ok)
            assert.are.same({ "setsid", "-f", "/ue/Engine/Binaries/Linux/UnrealEditor" }, cmd)
        end)

        it("linux, no systemd-run, editor binary present -> ok, setsid", function()
            on("linux")
            local root = h.tmpdir()
            h.write(root, "Engine/Binaries/Linux/UnrealEditor")
            h.stub(engine, "EnginePath", root)
            local ok, cmd = engine.GetExecuteCmd()
            assert.is_true(ok)
            assert.are.same({ "setsid", "-f", vim.fs.joinpath(root, "Engine/Binaries/Linux/UnrealEditor") }, cmd)
        end)

        it("linux + systemd-run, editor binary present -> ok, own user unit", function()
            on("linux")
            withSystemdRun()
            local root = h.tmpdir()
            h.write(root, "Engine/Binaries/Linux/UnrealEditor")
            h.stub(engine, "EnginePath", root)
            local ok, cmd = engine.GetExecuteCmd()
            assert.is_true(ok)
            assert.are.same({
                "systemd-run",
                "--user",
                "--collect",
                "--quiet",
                "--",
                vim.fs.joinpath(root, "Engine/Binaries/Linux/UnrealEditor"),
            }, cmd)
        end)

        it("linux + systemd-run, editor binary missing -> not ok", function()
            on("linux")
            withSystemdRun()
            local ok, cmd = engine.GetExecuteCmd()
            assert.is_false(ok)
            assert.are.equal("systemd-run", cmd[1])
        end)

        it("mac, editor binary missing -> not ok, open -n -a bundle", function()
            on("mac")
            assert.are.equal("Mac", system.GetPlatform())
            local ok, cmd = engine.GetExecuteCmd()
            assert.is_false(ok)
            assert.are.same({ "open", "-n", "-a", "/ue/Engine/Binaries/Mac/UnrealEditor.app", "--args" }, cmd)
        end)

        it("mac, editor binary present -> ok, bundle path not inner binary", function()
            on("mac")
            local root = h.tmpdir()
            h.write(root, "Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor")
            h.stub(engine, "EnginePath", root)
            local ok, cmd = engine.GetExecuteCmd()
            assert.is_true(ok)
            assert.are.same(
                { "open", "-n", "-a", vim.fs.joinpath(root, "Engine/Binaries/Mac/UnrealEditor.app"), "--args" },
                cmd
            )
        end)

        it("mac ignores systemd-run", function()
            on("mac")
            withSystemdRun()
            local _, cmd = engine.GetExecuteCmd()
            assert.are.equal("open", cmd[1])
        end)
    end)

    describe("InstalledEngines", function()
        local function use_sources(sources)
            h.stub(pathUtils, "FindEngineInstalledFiles", function()
                return sources
            end)
        end

        local function launcher_json(installs)
            local list = {}
            for name, location in pairs(installs) do
                table.insert(list, { AppName = name, InstallLocation = location, AppVersion = name })
            end
            local path = vim.fs.joinpath(h.tmpdir(), "LauncherInstalled.dat")
            vim.fn.writefile({ vim.json.encode({ InstallationList = list }) }, path)
            return { path = path, type = "json" }
        end

        local function install_ini(installs)
            local lines = { "[Installations]" }
            for id, location in pairs(installs) do
                table.insert(lines, id .. "=" .. location)
            end
            local path = vim.fs.joinpath(h.tmpdir(), "Install.ini")
            vim.fn.writefile(lines, path)
            return { path = path, type = "ini" }
        end

        local function installed_paths()
            local paths = {}
            for _, e in ipairs(engine.InstalledEngines) do
                table.insert(paths, e.path)
            end
            table.sort(paths)
            return paths
        end

        local function sorted(list)
            table.sort(list)
            return list
        end

        before_each(function()
            fresh_lockfile()
            h.project({})
        end)

        it("no source files -> empty", function()
            use_sources({})
            engine.init()
            assert.are.same({}, engine.InstalledEngines)
        end)

        it("source file missing on disk -> empty, no notify", function()
            use_sources({ { path = vim.fs.joinpath(h.tmpdir(), "LauncherInstalled.dat"), type = "json" } })
            engine.init()
            assert.are.same({}, engine.InstalledEngines)
            assert.are.equal(0, #notes)
        end)

        it("LauncherInstalled.dat with 2 valid installs -> both paths", function()
            local a, b = fake_engine(), fake_engine()
            use_sources({ launcher_json({ ["UE_5.3"] = a, ["UE_5.4"] = b }) })
            engine.init()
            assert.are.equal(2, #engine.InstalledEngines)
            assert.are.same(sorted({ a, b }), installed_paths())
        end)

        it("LauncherInstalled.dat entries keep AppName as id", function()
            local a = fake_engine()
            use_sources({ launcher_json({ ["UE_5.4"] = a }) })
            engine.init()
            assert.are.same({ { id = "UE_5.4", path = a } }, engine.InstalledEngines)
        end)

        it("Install.ini with 2 valid installs -> both paths", function()
            local a, b = fake_engine(), fake_engine()
            use_sources({ install_ini({ ["UE_5.4"] = a, ["{6F3B1A2C-0000-0000-0000-000000000000}"] = b }) })
            engine.init()
            assert.are.equal(2, #engine.InstalledEngines)
            assert.are.same(sorted({ a, b }), installed_paths())
        end)

        it("invalid engine dir -> hidden, valid one kept", function()
            local valid, invalid = fake_engine(), h.tmpdir()
            use_sources({ launcher_json({ ["UE_5.3"] = invalid, ["UE_5.4"] = valid }) })
            engine.init()
            assert.are.same({ valid }, installed_paths())
        end)

        it("same path in two sources -> listed once", function()
            local a, b = fake_engine(), fake_engine()
            use_sources({ launcher_json({ ["UE_5.4"] = a }), install_ini({ ["UE_5.4"] = a, ["UE_5.3"] = b }) })
            engine.init()
            assert.are.same(sorted({ a, b }), installed_paths())
        end)

        it("malformed LauncherInstalled.dat -> skipped, other sources kept", function()
            local a = fake_engine()
            local bad = vim.fs.joinpath(h.tmpdir(), "LauncherInstalled.dat")
            vim.fn.writefile({ "{ not json" }, bad)
            use_sources({ { path = bad, type = "json" }, install_ini({ ["UE_5.4"] = a }) })
            engine.init()
            assert.are.same({ a }, installed_paths())
        end)

        describe("registry", function()
            local KEY = "HKCU\\Software\\Epic Games\\Unreal Engine\\Builds"

            local function reg_query(code, builds)
                local lines = { "", KEY }
                for id, location in pairs(builds or {}) do
                    table.insert(lines, "    " .. id .. "    REG_SZ    " .. location)
                end
                table.insert(lines, "")
                local stdout = table.concat(lines, "\r\n")
                return h.spy(vim, "system", function(_, _, on_exit)
                    on_exit({ code = code, stdout = code == 0 and stdout or "", stderr = code == 0 and "" or "ERROR" })
                    return {}
                end)
            end

            local function wait_for(count)
                vim.wait(1000, function()
                    return #engine.InstalledEngines >= count
                end)
            end

            before_each(function()
                use_sources({ { path = KEY, type = "reg" } })
            end)

            it("runs reg query on the Builds key", function()
                local calls = reg_query(0, {})
                engine.init()
                assert.are.same({ "reg", "query", KEY }, calls[1][1])
            end)

            it("2 valid builds -> both paths, GUID as id", function()
                local a, b = fake_engine(), fake_engine()
                local guidA = "{11111111-1111-1111-1111-111111111111}"
                local guidB = "{22222222-2222-2222-2222-222222222222}"
                reg_query(0, { [guidA] = a, [guidB] = b })
                engine.init()
                wait_for(2)
                assert.are.same(sorted({ a, b }), installed_paths())
                assert.are.equal(a, engine.FindEngine(guidA).path)
            end)

            it("build path with spaces -> kept whole", function()
                local root = vim.fs.joinpath(h.tmpdir(), "Epic Games", "UE Source")
                h.write(root, UBT)
                h.write(root, bundled_dotnet("8.0.300"))
                reg_query(0, { ["{33333333-3333-3333-3333-333333333333}"] = root })
                engine.init()
                wait_for(1)
                assert.are.same({ root }, installed_paths())
            end)

            it("invalid build dir -> hidden", function()
                reg_query(0, { ["{44444444-4444-4444-4444-444444444444}"] = h.tmpdir() })
                engine.init()
                vim.wait(50)
                assert.are.same({}, engine.InstalledEngines)
            end)

            it("key missing (reg exit 1) -> empty, no notify", function()
                reg_query(1)
                engine.init()
                vim.wait(50)
                assert.are.same({}, engine.InstalledEngines)
                assert.are.equal(1, #notes)
            end)

            it("registry and LauncherInstalled.dat -> both listed", function()
                local a, b = fake_engine(), fake_engine()
                use_sources({ launcher_json({ ["UE_5.4"] = a }), { path = KEY, type = "reg" } })
                reg_query(0, { ["{55555555-5555-5555-5555-555555555555}"] = b })
                engine.init()
                wait_for(2)
                assert.are.same(sorted({ a, b }), installed_paths())
            end)
        end)

        it("init twice -> not accumulated", function()
            local a = fake_engine()
            use_sources({ launcher_json({ ["UE_5.4"] = a }) })
            engine.init()
            engine.init()
            assert.are.same({ a }, installed_paths())
        end)
    end)
end)
