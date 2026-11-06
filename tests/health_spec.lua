local h = dofile("tests/helpers.lua")

describe("health", function()
    local report

    before_each(function()
        report = {}
        for _, kind in ipairs({ "start", "ok", "warn", "error", "info" }) do
            h.stub(vim.health, kind, function(msg, hint)
                table.insert(report, { kind = kind, msg = msg, hint = hint })
            end)
        end
    end)
    after_each(h.reset)

    local SYSTEM, PLUGINS, CORE = 1, 2, 3

    local function section(index)
        local sections = {}
        for _, r in ipairs(report) do
            if r.kind == "start" then
                table.insert(sections, {})
            elseif #sections > 0 then
                table.insert(sections[#sections], r)
            end
        end
        return sections[index] or {}
    end

    local function kinds(entries)
        return vim.tbl_map(function(r)
            return r.kind
        end, entries)
    end

    local function core_kinds()
        return kinds(section(CORE))
    end

    it("without setup() -> no error, warns setup() not called", function()
        h.unload()
        local ok = pcall(require("unreal.health").check)
        h.unload()
        assert.is_true(ok)
        assert.are.equal("warn", core_kinds()[1])
    end)

    describe("with a project", function()
        local engine, project

        before_each(function()
            h.project({})
            require("unreal.config").config()
            engine = require("unreal.engine")
            project = require("unreal.project")
            h.stub(engine, "InstalledEngines", {})
            h.stub(engine, "OverrideEnginePath", nil)
            h.stub(project, "UprojectPath", nil)
            h.stub(vim.fn, "exepath", function()
                return ""
            end)
            h.stub(vim.lsp, "is_enabled", function()
                return true
            end)
        end)

        local UBT = "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"
        local EDITOR = "Engine/Binaries/Linux/UnrealEditor"
        local DOTNET = "Engine/Binaries/ThirdParty/DotNet/8.0.300/linux-"
            .. require("unreal.system").GetArch()
            .. "/dotnet"

        local function choose_uproject(association)
            local data = association and { EngineAssociation = association } or {}
            project.UprojectPath = h.write(h.tmpdir(), "Game.uproject", { vim.json.encode(data) })
        end

        local function engine_with(files)
            h.stub(require("unreal.system"), "GetPlatform", function()
                return "Linux"
            end)
            local root = h.tmpdir()
            for _, f in ipairs(files) do
                h.write(root, f)
            end
            return root
        end

        local function with_version(root)
            h.write(root, "Engine/Build/Build.version", {
                vim.json.encode({ MajorVersion = 5, MinorVersion = 4, PatchVersion = 2 }),
            })
        end

        local function installed(files)
            local root = engine_with(files)
            h.stub(engine, "InstalledEngines", { { id = "UE_5.4", path = root } })
            choose_uproject("5.4")
            return root
        end

        it("setup() called -> ok", function()
            h.stub(require("unreal"), "inited", true)
            require("unreal.health").check()
            assert.are.equal("ok", core_kinds()[1])
        end)

        it("no uproject chosen -> warn with Project Select hint, engine not checked", function()
            require("unreal.health").check()
            assert.are.same({ "warn", "warn" }, core_kinds())
            assert.are.equal("Run :Unreal Project Select", section(CORE)[2].hint)
        end)

        for _, case in ipairs({
            {
                name = "installed engine, all tools and version",
                files = { UBT, EDITOR, DOTNET },
                version = true,
                kinds = { "warn", "ok", "ok", "ok", "ok", "ok", "ok" },
                texts = { [4] = "5.4.2", [6] = "Bundled .NET" },
            },
            {
                name = "installed engine, UBT only",
                files = { UBT },
                kinds = { "warn", "ok", "ok", "warn", "warn", "warn", "ok" },
                texts = { [4] = "version" },
            },
            {
                name = "installed engine, no bundled dotnet, system dotnet on PATH",
                files = { UBT, EDITOR },
                pathDotnet = true,
                kinds = { "warn", "ok", "ok", "warn", "ok", "ok", "ok" },
                texts = { [6] = "System .NET" },
            },
            {
                name = "override with all tools",
                files = { UBT, EDITOR, DOTNET },
                override = true,
                kinds = { "warn", "ok", "warn", "warn", "ok", "ok", "ok" },
                texts = { [3] = "Overridden" },
            },
            {
                name = "override with editor only",
                files = { EDITOR },
                override = true,
                kinds = { "warn", "ok", "warn", "warn", "ok", "warn", "warn" },
                texts = {},
            },
            {
                name = "associated engine not installed",
                kinds = { "warn", "ok", "error", "warn", "warn", "warn", "warn" },
                texts = { [3] = "Engine SetPath" },
            },
        }) do
            it(case.name .. " -> " .. table.concat(case.kinds, " "), function()
                if case.pathDotnet then
                    h.stub(vim.fn, "exepath", function()
                        return "/usr/bin/dotnet"
                    end)
                end
                local root
                if case.override then
                    root = engine_with(case.files)
                    engine.OverrideEnginePath = root
                    choose_uproject("5.4")
                elseif case.files then
                    root = installed(case.files)
                else
                    choose_uproject("5.4")
                end
                if case.version then
                    with_version(root)
                end
                require("unreal.health").check()
                local core = section(CORE)
                assert.are.same(case.kinds, kinds(core))
                assert.is_not_nil(core[2].msg:find(project.UprojectPath, 1, true))
                if root then
                    assert.is_not_nil(core[3].msg:find(root, 1, true))
                end
                for index, text in pairs(case.texts) do
                    assert.is_not_nil((core[index].msg .. (core[index].hint or "")):find(text, 1, true), text)
                end
            end)
        end

        it("uproject without EngineAssociation -> error, no crash", function()
            choose_uproject(nil)
            local ok = pcall(require("unreal.health").check)
            assert.is_true(ok)
            assert.are.equal("error", core_kinds()[3])
        end)

        for i, exe in ipairs({ "rg", "clangd" }) do
            it("missing " .. exe .. " -> error with hint", function()
                h.stub(vim.fn, "executable", function(name)
                    return name == exe and 0 or 1
                end)
                h.stub(vim.fn, "system", function()
                    return "x 1.0\n"
                end)
                require("unreal.health").check()
                local expected = { "ok", "ok" }
                expected[i] = "error"
                assert.are.same(expected, kinds(section(SYSTEM)))
                assert.is_not_nil(section(SYSTEM)[i].hint)
            end)
        end

        for _, case in ipairs({
            { "succeeds -> version shown", "true", true },
            { "fails -> version hidden", "false", false },
        }) do
            it("executable present, --version " .. case[1], function()
                h.stub(vim.fn, "executable", function()
                    return 1
                end)
                h.stub(vim.fn, "system", function()
                    vim.cmd("silent! call system('" .. case[2] .. "')")
                    return "fake 9.9.9\n"
                end)
                require("unreal.health").check()
                assert.are.same({ "ok", "ok" }, kinds(section(SYSTEM)))
                assert.are.equal(case[3], section(SYSTEM)[1].msg:find("fake 9.9.9", 1, true) ~= nil)
            end)
        end

        it("telescope missing -> error", function()
            require("unreal.config").config({ extensions = { telescope = true } })
            h.stub(package.loaded, "telescope", nil)
            h.stub(package.preload, "telescope", function()
                error("not found")
            end)
            require("unreal.health").check()
            assert.are.same({ "error", "ok", "ok" }, kinds(section(PLUGINS)))
        end)

        it("telescope present -> ok", function()
            require("unreal.config").config({ extensions = { telescope = true } })
            h.stub(package.loaded, "telescope", {})
            require("unreal.health").check()
            assert.are.same({ "ok", "ok", "ok" }, kinds(section(PLUGINS)))
        end)

        for _, value in ipairs({ "nil", false }) do
            it("telescope extension " .. tostring(value) .. " -> telescope not checked", function()
                require("unreal.config").config({ extensions = { telescope = value ~= "nil" and value or nil } })
                h.stub(package.loaded, "telescope", nil)
                h.stub(package.preload, "telescope", function()
                    error("not found")
                end)
                require("unreal.health").check()
                assert.are.same({ "ok", "ok" }, kinds(section(PLUGINS)))
            end)
        end

        it("plenary missing -> error with hint", function()
            h.stub(package.loaded, "plenary", nil)
            h.stub(package.preload, "plenary", function()
                error("not found")
            end)
            require("unreal.health").check()
            assert.are.same({ "error", "ok" }, kinds(section(PLUGINS)))
            assert.is_not_nil(section(PLUGINS)[1].hint)
        end)

        it("plenary present -> ok", function()
            h.stub(package.loaded, "plenary", {})
            require("unreal.health").check()
            assert.are.same({ "ok", "ok" }, kinds(section(PLUGINS)))
        end)

        it("clangd enabled -> ok", function()
            local calls = h.spy(vim.lsp, "is_enabled", true)
            require("unreal.health").check()
            local entries = section(PLUGINS)
            assert.are.equal("ok", entries[#entries].kind)
            assert.are.same({ "clangd" }, calls[1])
        end)

        it("clangd not enabled -> warn with vim.lsp.enable hint", function()
            h.stub(vim.lsp, "is_enabled", function()
                return false
            end)
            require("unreal.health").check()
            local entries = section(PLUGINS)
            assert.are.equal("warn", entries[#entries].kind)
            assert.is_not_nil(entries[#entries].hint:find("vim.lsp.enable", 1, true))
        end)
    end)
end)
