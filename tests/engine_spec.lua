local h = dofile("tests/helpers.lua")

local config = require("unreal.config")
local engine = require("unreal.engine")
local system = require("unreal.system")
local pathUtils = require("unreal.path_utils")

local UBT = h.UBT

local function fake_engine()
    local root = h.tmpdir()
    h.write(root, UBT)
    h.write_version(root)
    return root
end

describe("engine", function()
    local notes

    before_each(function()
        config.config()
        notes = h.notifications()
        h.stub(engine, "OverrideEnginePath", nil)
    end)
    after_each(h.reset)

    describe("ParseUbtPath", function()
        it("engine dir without RunUBT script -> false, expected path", function()
            local root = h.tmpdir()
            local ok, path = engine.ParseUbtPath(root)
            assert.is_false(ok)
            assert.are.equal(vim.fs.joinpath(root, UBT), path)
        end)

        it("engine dir with RunUBT script -> true, script path", function()
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

    describe("IsRootEngineDirValid", function()
        it("Build.version present -> true", function()
            local root = h.tmpdir()
            h.write_version(root)
            assert.is_true(engine.IsRootEngineDirValid(root))
        end)

        it("Build.version present, no RunUBT -> true", function()
            local root = h.tmpdir()
            h.write_version(root)
            assert.is_true(engine.IsRootEngineDirValid(root))
            assert.is_false(engine.ParseUbtPath(root))
        end)

        it("RunUBT only, no Build.version -> false", function()
            local root = h.tmpdir()
            h.write(root, UBT)
            assert.is_false(engine.IsRootEngineDirValid(root))
        end)

        it("malformed Build.version -> false", function()
            local root = h.tmpdir()
            h.write(root, h.VERSION_FILE, { "{ not json" })
            assert.is_false(engine.IsRootEngineDirValid(root))
        end)

        it("empty folder -> false", function()
            assert.is_false(engine.IsRootEngineDirValid(h.tmpdir()))
        end)

        it("nil -> false", function()
            assert.is_false(engine.IsRootEngineDirValid(nil))
        end)
    end)

    describe("InputEnginePath", function()
        for _, case in ipairs({ { "cancel (nil)", nil }, { "empty string", "" } }) do
            it(case[1] .. " -> callback(nil)", function()
                h.answer_input(case[2])
                local got = "unset"
                engine.InputEnginePath(function(path)
                    got = path
                end)
                assert.is_nil(got)
            end)
        end

        it("typed text -> callback(text)", function()
            h.answer_input("/ue")
            local got
            engine.InputEnginePath(function(path)
                got = path
            end)
            assert.are.equal("/ue", got)
        end)
    end)

    describe("SetEnginePath_User / ClearEnginePath_User", function()
        it("valid engine folder -> override set, info notify", function()
            local root = fake_engine()
            h.answer_input(root)
            engine.SetEnginePath_User()
            assert.are.equal(root, engine.OverrideEnginePath)
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
        end)

        it("invalid folder -> warn, previous override kept", function()
            local root = fake_engine()
            engine.OverrideEnginePath = root
            h.answer_input(h.tmpdir())
            engine.SetEnginePath_User()
            assert.are.equal(root, engine.OverrideEnginePath)
            assert.is_true(h.notified(notes, vim.log.levels.WARN))
        end)

        it("prompt cancelled -> warn, no override", function()
            h.answer_input(nil)
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
            assert.are.equal("5.4", engine.GetAssociatedEngine(h.write_uproject(h.tmpdir(), "5.4")))
        end)

        it("no EngineAssociation field -> nil", function()
            assert.is_nil(engine.GetAssociatedEngine(h.write_uproject(h.tmpdir(), nil)))
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

        local function assert_fields(expected, actual)
            for key, value in pairs(expected) do
                assert.are.same(value, actual[key], key)
            end
        end

        before_each(function()
            h.stub(system, "GetPlatform", function()
                return "Linux"
            end)
            h.stub(vim.fn, "executable", function()
                return 0
            end)
        end)

        it("editor and UBT -> all tools", function()
            local root = fake_engine()
            h.write(root, EDITOR)
            assert_fields({
                RootDir = root,
                Version = "5.4.2",
                BuildConfig = vim.fs.joinpath(root, "Engine/Saved/UnrealBuildTool/BuildConfiguration.xml"),
                EngineExe = { "setsid", "-f", vim.fs.joinpath(root, EDITOR) },
                UnrealBuildTool = vim.fs.joinpath(root, UBT),
            }, engine.RetrieveTools(root))
        end)

        it("no editor -> UBT kept, no EngineExe", function()
            local root = fake_engine()
            local tools = engine.RetrieveTools(root)
            assert.is_nil(tools.EngineExe)
            assert.are.equal(vim.fs.joinpath(root, UBT), tools.UnrealBuildTool)
        end)

        it("empty folder -> no tools, RootDir kept", function()
            local root = h.tmpdir()
            local tools = engine.RetrieveTools(root)
            assert.are.equal(root, tools.RootDir)
            assert.is_nil(tools.EngineExe)
            assert.is_nil(tools.UnrealBuildTool)
        end)
    end)

    describe("ParseBuildConfiguration", function()
        it("engine dir -> Engine/Saved/UnrealBuildTool/BuildConfiguration.xml", function()
            assert.are.equal(
                vim.fs.joinpath("/ue", "Engine/Saved/UnrealBuildTool/BuildConfiguration.xml"),
                engine.ParseBuildConfiguration("/ue")
            )
        end)

        it("nil engine dir -> nil", function()
            assert.is_nil(engine.ParseBuildConfiguration(nil))
        end)
    end)

    describe("GetEngineVersion", function()
        it("Build.version present -> major.minor.patch", function()
            local root = h.tmpdir()
            h.write(root, "Engine/Build/Build.version", {
                vim.json.encode({ MajorVersion = 5, MinorVersion = 4, PatchVersion = 2, Changelist = 0 }),
            })
            assert.are.equal("5.4.2", engine.GetEngineVersion(root))
        end)

        it("nil engine path -> 0.0.0", function()
            assert.are.equal("0.0.0", engine.GetEngineVersion(nil))
        end)

        it("Build.version missing -> 0.0.0", function()
            assert.are.equal("0.0.0", engine.GetEngineVersion(h.tmpdir()))
        end)

        it("read-only Build.version -> still read", function()
            local root = h.tmpdir()
            local file = h.write(root, "Engine/Build/Build.version", {
                vim.json.encode({ MajorVersion = 5, MinorVersion = 4, PatchVersion = 2 }),
            })
            vim.uv.fs_chmod(file, tonumber("444", 8))
            assert.are.equal("5.4.2", engine.GetEngineVersion(root))
        end)

        it("Build.version with JSON null -> 0.0.0, no error", function()
            local root = h.tmpdir()
            h.write(root, "Engine/Build/Build.version", { "null" })
            assert.are.equal("0.0.0", engine.GetEngineVersion(root))
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
            prompts = h.answer_input(value)
        end

        before_each(function()
            uproject = h.write_uproject(h.tmpdir(), "5.4")
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
            uproject = h.write_uproject(h.tmpdir(), nil)
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
        local EDITORS = {
            win32 = "Engine/Binaries/Win64/UnrealEditor.exe",
            linux = "Engine/Binaries/Linux/UnrealEditor",
            mac = "Engine/Binaries/Mac/UnrealEditor.app",
        }

        local function on(feature, systemdRun)
            h.stub(vim.fn, "has", function(name)
                return name == feature and 1 or 0
            end)
            h.stub(vim.fn, "executable", function(name)
                return (systemdRun and name == "systemd-run") and 1 or 0
            end)
        end

        for feature, platform in pairs({ win32 = "Win64", linux = "Linux", mac = "Mac" }) do
            it(feature .. " -> platform " .. platform, function()
                on(feature, false)
                assert.are.equal(platform, system.GetPlatform())
            end)
        end

        it("nil engine path -> not ok", function()
            on("linux", false)
            assert.is_false((engine.GetExecuteCmd(nil)))
        end)

        for _, case in ipairs({
            {
                "win32",
                false,
                function(exe)
                    return { exe }
                end,
            },
            {
                "linux",
                false,
                function(exe)
                    return { "setsid", "-f", exe }
                end,
            },
            {
                "linux",
                true,
                function(exe)
                    return { "systemd-run", "--user", "--collect", "--quiet", "--", exe }
                end,
            },
            {
                "mac",
                false,
                function(exe)
                    return { "open", "-n", "-a", exe, "--args" }
                end,
            },
            {
                "mac",
                true,
                function(exe)
                    return { "open", "-n", "-a", exe, "--args" }
                end,
            },
        }) do
            local feature, systemdRun, expected = case[1], case[2], case[3]
            for _, present in ipairs({ true, false }) do
                local name = ("%s, systemd-run %s, editor %s -> %s"):format(
                    feature,
                    systemdRun and "on" or "off",
                    present and "present" or "missing",
                    present and "ok" or "not ok"
                )
                it(name, function()
                    on(feature, systemdRun)
                    local root = h.tmpdir()
                    if present then
                        h.write(
                            root,
                            feature == "mac" and EDITORS.mac .. "/Contents/MacOS/UnrealEditor" or EDITORS[feature]
                        )
                    end
                    local ok, cmd = engine.GetExecuteCmd(root)
                    assert.are.equal(present, ok)
                    assert.are.same(expected(vim.fs.joinpath(root, EDITORS[feature])), cmd)
                end)
            end
        end
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

        it("same id in two sources -> listed once", function()
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

            local function init_and_wait(sources)
                local appends = h.spy(engine, "AppendEngines", engine.AppendEngines)
                engine.init()
                assert.is_true(vim.wait(1000, function()
                    return #appends >= (sources or 1)
                end))
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
                init_and_wait()
                assert.are.same(sorted({ a, b }), installed_paths())
                assert.are.equal(a, engine.FindEngine(guidA).path)
            end)

            it("build path with spaces -> kept whole", function()
                local root = vim.fs.joinpath(h.tmpdir(), "Epic Games", "UE Source")
                h.write(root, UBT)
                h.write_version(root)
                reg_query(0, { ["{33333333-3333-3333-3333-333333333333}"] = root })
                init_and_wait()
                assert.are.same({ root }, installed_paths())
            end)

            it("invalid build dir -> hidden", function()
                reg_query(0, { ["{44444444-4444-4444-4444-444444444444}"] = h.tmpdir() })
                init_and_wait()
                assert.are.same({}, engine.InstalledEngines)
            end)

            it("key missing (reg exit 1) -> empty, error notify", function()
                reg_query(1)
                init_and_wait()
                assert.are.same({}, engine.InstalledEngines)
                assert.is_true(h.notified(notes, vim.log.levels.ERROR, "(1)"))
            end)

            it("registry and LauncherInstalled.dat -> both listed", function()
                local a, b = fake_engine(), fake_engine()
                use_sources({ launcher_json({ ["UE_5.4"] = a }), { path = KEY, type = "reg" } })
                reg_query(0, { ["{55555555-5555-5555-5555-555555555555}"] = b })
                init_and_wait(2)
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
