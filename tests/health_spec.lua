local h = dofile("tests/helpers.lua")
vim.env.XDG_DATA_HOME = h.tmpdir()

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

    describe("after setup()", function()
        before_each(function()
            h.project({})
            require("unreal.config").config()
            local engine = require("unreal.engine")
            engine.init()
            h.stub(engine, "LockFilePath", vim.fs.joinpath(h.tmpdir(), "lock.dat"))
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

        local function save_engine_path(path)
            local engine = require("unreal.engine")
            vim.fn.writefile({ vim.json.encode({ [vim.fn.getcwd()] = path }) }, engine.LockFilePath)
        end

        ---@param files string[] files to create under a fresh engine dir
        local function engine_with(files)
            h.stub(require("unreal.system"), "GetPlatform", function()
                return "Linux"
            end)
            local root = h.tmpdir()
            for _, f in ipairs(files) do
                h.write(root, f)
            end
            save_engine_path(root)
            return root
        end

        it("setup() called -> ok", function()
            h.stub(require("unreal"), "inited", true)
            require("unreal.health").check()
            assert.are.equal("ok", core_kinds()[1])
        end)

        it("no engine path -> warn with SetEnginePath hint, rest warned", function()
            require("unreal.health").check()
            assert.are.same({ "warn", "warn", "warn", "warn", "warn" }, core_kinds())
            assert.is_not_nil(section(CORE)[2].hint)
        end)

        it("UBT, editor and bundled dotnet present -> all ok, dotnet reported as bundled", function()
            engine_with({ UBT, EDITOR, DOTNET })
            require("unreal.health").check()
            assert.are.same({ "warn", "ok", "ok", "ok", "ok" }, core_kinds())
            assert.is_not_nil(section(CORE)[4].msg:find("Bundled DotNet", 1, true))
        end)

        it("saved path with nothing in it -> path ok, rest warned", function()
            engine_with({})
            require("unreal.health").check()
            assert.are.same({ "warn", "ok", "warn", "warn", "warn" }, core_kinds())
        end)

        it("UBT only -> editor and dotnet warned", function()
            engine_with({ UBT })
            require("unreal.health").check()
            assert.are.same({ "warn", "ok", "warn", "warn", "ok" }, core_kinds())
        end)

        it("editor only -> dotnet and UBT warned", function()
            engine_with({ EDITOR })
            require("unreal.health").check()
            assert.are.same({ "warn", "ok", "ok", "warn", "warn" }, core_kinds())
        end)

        it("no bundled dotnet, system dotnet on PATH -> ok, reported as system", function()
            h.stub(vim.fn, "exepath", function()
                return "/usr/bin/dotnet"
            end)
            engine_with({ UBT, EDITOR })
            require("unreal.health").check()
            assert.are.same({ "warn", "ok", "ok", "ok", "ok" }, core_kinds())
            assert.is_not_nil(section(CORE)[4].msg:find("System DotNet", 1, true))
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
