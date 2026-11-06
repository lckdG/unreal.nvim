local h = dofile("tests/helpers.lua")

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

local function write_uproject(root, association)
    local data = association and { EngineAssociation = association } or {}
    return h.write(root, "Game.uproject", { vim.json.encode(data) })
end

describe("engine", function()
    local notes

    before_each(function()
        config.config()
        notes = h.notifications()
        h.stub(vim.fn, "exepath", function()
            return ""
        end)
        h.stub(engine, "OverrideEnginePath", nil)
    end)
    after_each(h.reset)

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

        it("nil engine dir -> false, nil", function()
            local ok, path = engine.ParseUbtPath(nil)
            assert.is_false(ok)
            assert.is_nil(path)
        end)
    end)

    describe("ParseDotnetPath", function()
        local function no_system_dotnet()
            h.stub(vim.fn, "exepath", function()
                return ""
            end)
        end

        it("nil engine dir, no system dotnet -> false, nil", function()
            local ok, path = engine.ParseDotnetPath(nil)
            assert.is_false(ok)
            assert.is_nil(path)
        end)

        it("nil engine dir, system dotnet -> false, system path", function()
            h.stub(vim.fn, "exepath", function()
                return "/usr/bin/dotnet"
            end)
            local ok, path = engine.ParseDotnetPath(nil)
            assert.is_false(ok)
            assert.are.equal("/usr/bin/dotnet", path)
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

        it("unknown arch, no system dotnet -> false, nil", function()
            h.stub(require("unreal.system"), "GetArch", function()
                return nil
            end)
            local ok, path = engine.ParseDotnetPath(fake_engine())
            assert.is_false(ok)
            assert.is_nil(path)
        end)

        it("unknown arch, system dotnet -> false, system path", function()
            h.stub(require("unreal.system"), "GetArch", function()
                return nil
            end)
            h.stub(vim.fn, "exepath", function()
                return "/usr/bin/dotnet"
            end)
            local ok, path = engine.ParseDotnetPath(fake_engine())
            assert.is_false(ok)
            assert.are.equal("/usr/bin/dotnet", path)
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

    describe("InputEnginePath", function()
        for _, case in ipairs({ { "cancel (nil)", nil }, { "empty string", "" } }) do
            it(case[1] .. " -> callback(nil)", function()
                h.stub(vim.ui, "input", function(_, cb)
                    cb(case[2])
                end)
                local got = "unset"
                engine.InputEnginePath(function(path)
                    got = path
                end)
                assert.is_nil(got)
            end)
        end

        it("typed text -> callback(text)", function()
            h.stub(vim.ui, "input", function(_, cb)
                cb("/ue")
            end)
            local got
            engine.InputEnginePath(function(path)
                got = path
            end)
            assert.are.equal("/ue", got)
        end)
    end)

    describe("SetEnginePath_User / ClearEnginePath_User", function()
        local function answer(value)
            h.stub(vim.ui, "input", function(_, cb)
                cb(value)
            end)
        end

        it("valid engine folder -> override set, info notify", function()
            local root = fake_engine()
            answer(root)
            engine.SetEnginePath_User()
            assert.are.equal(root, engine.OverrideEnginePath)
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
        end)

        it("invalid folder -> warn, previous override kept", function()
            local root = fake_engine()
            engine.OverrideEnginePath = root
            answer(h.tmpdir())
            engine.SetEnginePath_User()
            assert.are.equal(root, engine.OverrideEnginePath)
            assert.is_true(h.notified(notes, vim.log.levels.WARN))
        end)

        it("prompt cancelled -> warn, no override", function()
            answer(nil)
            engine.SetEnginePath_User()
            assert.is_nil(engine.OverrideEnginePath)
            assert.is_true(h.notified(notes, vim.log.levels.WARN))
        end)

        it("ClearEnginePath_User -> override nil, info notify", function()
            engine.OverrideEnginePath = fake_engine()
            engine.ClearEnginePath_User()
            assert.is_nil(engine.OverrideEnginePath)
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
        end)
    end)

    describe("FindEngine", function()
        before_each(function()
            h.stub(engine, "InstalledEngines", {
                { id = "UE_5.4", path = "/ue54" },
                { id = "{11111111-1111-1111-1111-111111111111}", path = "/src" },
            })
        end)

        it("nil id -> nil", function()
            assert.is_nil(engine.FindEngine(nil))
        end)

        it("exact id -> match", function()
            assert.are.equal("/ue54", engine.FindEngine("UE_5.4").path)
            assert.are.equal("/src", engine.FindEngine("{11111111-1111-1111-1111-111111111111}").path)
        end)

        it("version without UE_ prefix -> launcher install", function()
            assert.are.equal("/ue54", engine.FindEngine("5.4").path)
        end)

        it("unknown id -> nil", function()
            assert.is_nil(engine.FindEngine("5.3"))
        end)
    end)

    describe("GetAssociatedEngine", function()
        it("EngineAssociation field -> its value", function()
            assert.are.equal("5.4", engine.GetAssociatedEngine(write_uproject(h.tmpdir(), "5.4")))
        end)

        it("no EngineAssociation field -> nil", function()
            assert.is_nil(engine.GetAssociatedEngine(write_uproject(h.tmpdir(), nil)))
        end)

        it("invalid JSON -> nil", function()
            assert.is_nil(engine.GetAssociatedEngine(h.write(h.tmpdir(), "Game.uproject", { "{ not json" })))
        end)

        it("missing file -> nil", function()
            assert.is_nil(engine.GetAssociatedEngine(vim.fs.joinpath(h.tmpdir(), "Game.uproject")))
        end)
    end)

    describe("RetrieveTools", function()
        local EDITOR = "Engine/Binaries/Linux/UnrealEditor"

        before_each(function()
            h.stub(system, "GetPlatform", function()
                return "Linux"
            end)
            h.stub(vim.fn, "executable", function()
                return 0
            end)
        end)

        it("editor, dotnet and UBT -> all tools", function()
            local root = fake_engine()
            h.write(root, EDITOR)
            local tools = engine.RetrieveTools(root)
            assert.are.same({
                RootDir = root,
                EngineExe = { "setsid", "-f", vim.fs.joinpath(root, EDITOR) },
                DotNetExe = vim.fs.joinpath(root, bundled_dotnet("8.0.300")),
                UnrealBuildTool = vim.fs.joinpath(root, UBT),
            }, tools)
        end)

        it("no editor -> dotnet and UBT kept, no EngineExe", function()
            local root = fake_engine()
            local tools = engine.RetrieveTools(root)
            assert.is_nil(tools.EngineExe)
            assert.are.equal(vim.fs.joinpath(root, UBT), tools.UnrealBuildTool)
            assert.is_not_nil(tools.DotNetExe)
        end)

        it("empty folder, no system dotnet -> only RootDir", function()
            local root = h.tmpdir()
            assert.are.same({ RootDir = root }, engine.RetrieveTools(root))
        end)
    end)

    describe("FindEngineTools", function()
        local prompts, uproject

        local function find()
            local result = "unset"
            engine.FindEngineTools(uproject, function(tools)
                result = tools
            end)
            return result
        end

        local function answer(value)
            prompts = h.spy(vim.ui, "input", function(_, cb)
                cb(value)
            end)
        end

        before_each(function()
            uproject = write_uproject(h.tmpdir(), "5.4")
            h.stub(engine, "InstalledEngines", {})
            answer(nil)
        end)

        it("override set -> its tools, no prompt", function()
            local root = fake_engine()
            engine.OverrideEnginePath = root
            h.stub(engine, "InstalledEngines", { { id = "UE_5.4", path = fake_engine() } })
            assert.are.equal(root, find().RootDir)
            assert.are.equal(0, #prompts)
        end)

        it("associated launcher engine installed -> its tools, no prompt", function()
            local root = fake_engine()
            h.stub(engine, "InstalledEngines", { { id = "UE_5.4", path = root } })
            assert.are.equal(root, find().RootDir)
            assert.are.equal(0, #prompts)
        end)

        it("associated engine not installed -> prompt, typed valid folder used", function()
            local root = fake_engine()
            answer(root)
            assert.are.equal(root, find().RootDir)
            assert.are.equal(1, #prompts)
        end)

        it("no EngineAssociation -> prompt", function()
            uproject = write_uproject(h.tmpdir(), nil)
            local root = fake_engine()
            answer(root)
            assert.are.equal(root, find().RootDir)
            assert.are.equal(1, #prompts)
        end)

        it("typed folder is not remembered -> asked again next time", function()
            answer(fake_engine())
            find()
            find()
            assert.are.equal(2, #prompts)
        end)

        it("prompt cancelled -> callback(nil)", function()
            assert.is_nil(find())
        end)

        it("typed invalid folder -> callback(nil)", function()
            answer(h.tmpdir())
            assert.is_nil(find())
        end)
    end)

    describe("GetExecuteCmd", function()
        local function on(platform)
            h.stub(vim.fn, "has", function(feature)
                return feature == platform and 1 or 0
            end)
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

        it("nil engine path -> not ok", function()
            on("linux")
            local ok = engine.GetExecuteCmd(nil)
            assert.is_false(ok)
        end)

        it("win32, editor missing -> not ok, UnrealEditor.exe path", function()
            on("win32")
            assert.are.equal("Win64", system.GetPlatform())
            local ok, cmd = engine.GetExecuteCmd("/ue")
            assert.is_false(ok)
            assert.are.same({ vim.fs.joinpath("/ue", "Engine/Binaries/Win64/UnrealEditor.exe") }, cmd)
        end)

        it("win32, editor present -> ok, runs UnrealEditor.exe directly", function()
            on("win32")
            local root = h.tmpdir()
            local exe = h.write(root, "Engine/Binaries/Win64/UnrealEditor.exe")
            local ok, cmd = engine.GetExecuteCmd(root)
            assert.is_true(ok)
            assert.are.same({ exe }, cmd)
        end)

        it("linux, no systemd-run, editor binary missing -> not ok, setsid", function()
            on("linux")
            assert.are.equal("Linux", system.GetPlatform())
            local ok, cmd = engine.GetExecuteCmd("/ue")
            assert.is_false(ok)
            assert.are.same({ "setsid", "-f", "/ue/Engine/Binaries/Linux/UnrealEditor" }, cmd)
        end)

        it("linux, no systemd-run, editor binary present -> ok, setsid", function()
            on("linux")
            local root = h.tmpdir()
            h.write(root, "Engine/Binaries/Linux/UnrealEditor")
            local ok, cmd = engine.GetExecuteCmd(root)
            assert.is_true(ok)
            assert.are.same({ "setsid", "-f", vim.fs.joinpath(root, "Engine/Binaries/Linux/UnrealEditor") }, cmd)
        end)

        it("linux + systemd-run, editor binary present -> ok, own user unit", function()
            on("linux")
            withSystemdRun()
            local root = h.tmpdir()
            h.write(root, "Engine/Binaries/Linux/UnrealEditor")
            local ok, cmd = engine.GetExecuteCmd(root)
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
            local ok, cmd = engine.GetExecuteCmd("/ue")
            assert.is_false(ok)
            assert.are.equal("systemd-run", cmd[1])
        end)

        it("mac, editor binary missing -> not ok, open -n -a bundle", function()
            on("mac")
            assert.are.equal("Mac", system.GetPlatform())
            local ok, cmd = engine.GetExecuteCmd("/ue")
            assert.is_false(ok)
            assert.are.same({ "open", "-n", "-a", "/ue/Engine/Binaries/Mac/UnrealEditor.app", "--args" }, cmd)
        end)

        it("mac, editor binary present -> ok, bundle path not inner binary", function()
            on("mac")
            local root = h.tmpdir()
            h.write(root, "Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor")
            local ok, cmd = engine.GetExecuteCmd(root)
            assert.is_true(ok)
            assert.are.same(
                { "open", "-n", "-a", vim.fs.joinpath(root, "Engine/Binaries/Mac/UnrealEditor.app"), "--args" },
                cmd
            )
        end)

        it("mac ignores systemd-run", function()
            on("mac")
            withSystemdRun()
            local _, cmd = engine.GetExecuteCmd("/ue")
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
