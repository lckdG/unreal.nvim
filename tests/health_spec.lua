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

    local function find(kind, pattern)
        for _, r in ipairs(report) do
            if r.kind == kind and r.msg:find(pattern, 1, true) then return r end
        end
    end

    it("without setup() -> no error, warns setup() not called", function()
        h.unload()
        local ok, err = pcall(require("unreal.health").check)
        h.unload()
        assert.is_true(ok, tostring(err))
        assert.is_not_nil(find("warn", "setup()"))
    end)

    describe("after setup()", function()
        before_each(function()
            h.project({})
            require("unreal.config").config()
            local engine = require("unreal.engine")
            engine.init()
            h.stub(engine, "LockFilePath", vim.fs.joinpath(h.tmpdir(), "lock.dat"))
        end)

        it("no engine path -> warn with SetEnginePath hint", function()
            require("unreal.health").check()
            local r = find("warn", "Missing a valid engine path")
            assert.is_not_nil(r)
            assert.are.equal("Run :Unreal SetEnginePath", r.hint)
        end)

        local function save_engine_path(path)
            local engine = require("unreal.engine")
            vim.fn.writefile({ vim.json.encode({ [vim.fn.getcwd()] = path }) }, engine.LockFilePath)
        end

        it("engine path with UnrealBuildTool.dll -> ok with path", function()
            local root = h.tmpdir()
            h.write(root, "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll")
            save_engine_path(root)
            require("unreal.health").check()
            assert.is_not_nil(find("ok", "Engine path found: " .. root))
        end)

        it("saved engine path without UnrealBuildTool.dll -> not ok, SetEnginePath hint", function()
            save_engine_path(h.tmpdir())
            require("unreal.health").check()
            assert.is_nil(find("ok", "Engine path found"))
            local r = find("warn", "Missing a valid engine path")
            assert.is_not_nil(r)
            assert.are.equal("Run :Unreal SetEnginePath", r.hint)
        end)

        for _, exe in ipairs({ "rg", "clangd", "dotnet" }) do
            it("missing " .. exe .. " -> error with hint", function()
                h.stub(vim.fn, "executable", function(name) return name == exe and 0 or 1 end)
                h.stub(vim.fn, "system", function() return "x 1.0\n" end)
                require("unreal.health").check()
                local r = find("error", exe .. " not found")
                assert.is_not_nil(r)
                assert.is_not_nil(r.hint)
            end)
        end

        it("executable present, --version fails -> ok without version", function()
            h.stub(vim.fn, "executable", function() return 1 end)
            h.stub(vim.fn, "system", function()
                vim.cmd("silent! call system('exit 1')")
                return ""
            end)
            require("unreal.health").check()
            assert.is_not_nil(find("ok", "rg found"))
            assert.is_nil(find("ok", "rg found ("))
        end)

        it("telescope missing -> error", function()
            require("unreal.health").check()
            assert.is_not_nil(find("error", "telescope.nvim not found"))
        end)
    end)
end)
