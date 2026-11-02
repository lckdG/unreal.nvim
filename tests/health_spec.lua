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

        local UBT = "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"
        local EDITOR = "Engine/Binaries/Linux/UnrealEditor"

        local function save_engine_path(path)
            local engine = require("unreal.engine")
            vim.fn.writefile({ vim.json.encode({ [vim.fn.getcwd()] = path }) }, engine.LockFilePath)
        end

        ---@param files string[] files to create under a fresh engine dir
        local function engine_with(files)
            h.stub(require("unreal.system"), "GetPlatform", function() return "Linux" end)
            local root = h.tmpdir()
            for _, f in ipairs(files) do h.write(root, f) end
            save_engine_path(root)
            return root
        end

        it("setup() called -> ok", function()
            h.stub(require("unreal"), "inited", true)
            require("unreal.health").check()
            assert.is_not_nil(find("ok", "Plugin is inited"))
        end)

        it("no engine path -> error summary, warn with SetEnginePath hint", function()
            require("unreal.health").check()
            assert.is_not_nil(find("error", "Required path(s) missing"))
            local r = find("warn", "Engine path not set")
            assert.is_not_nil(r)
            assert.are.equal("Run :Unreal SetEnginePath", r.hint)
            assert.is_not_nil(find("warn", "Executable path not found"))
            assert.is_not_nil(find("warn", "UBT path not found"))
            assert.is_nil(find("ok", "Executable path found"))
        end)

        it("UBT and editor present -> all ok", function()
            local root = engine_with({ UBT, EDITOR })
            require("unreal.health").check()
            assert.is_not_nil(find("ok", "All required paths found"))
            assert.is_not_nil(find("ok", "Engine path found: " .. root))
            assert.is_not_nil(find("ok", vim.fs.joinpath(root, EDITOR)))
            assert.is_not_nil(find("ok", vim.fs.joinpath(root, UBT)))
            assert.is_nil(find("error", "Required path(s) missing"))
        end)

        it("saved path with neither UBT nor editor -> error summary, both warned", function()
            local root = engine_with({})
            require("unreal.health").check()
            assert.is_not_nil(find("error", "Required path(s) missing"))
            assert.is_not_nil(find("ok", "Engine path found: " .. root))
            assert.is_not_nil(find("warn", "Executable path not found"))
            assert.is_not_nil(find("warn", "UBT path not found"))
        end)

        it("UBT only -> error summary, editor warned", function()
            engine_with({ UBT })
            require("unreal.health").check()
            assert.is_not_nil(find("error", "Required path(s) missing"))
            assert.is_not_nil(find("ok", "UBT path found"))
            assert.is_not_nil(find("warn", "Executable path not found"))
        end)

        it("editor only -> error summary, UBT warned", function()
            engine_with({ EDITOR })
            require("unreal.health").check()
            assert.is_not_nil(find("error", "Required path(s) missing"))
            assert.is_not_nil(find("ok", "Executable path found"))
            assert.is_not_nil(find("warn", "UBT path not found"))
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
            h.stub(package.loaded, "telescope", nil)
            h.stub(package.preload, "telescope", function() error("not found") end)
            require("unreal.health").check()
            assert.is_not_nil(find("error", "telescope.nvim not found"))
        end)

        it("telescope present -> ok", function()
            h.stub(package.loaded, "telescope", {})
            require("unreal.health").check()
            assert.is_not_nil(find("ok", "telescope.nvim found"))
        end)

        it("plenary missing -> error with hint", function()
            h.stub(package.loaded, "plenary", nil)
            h.stub(package.preload, "plenary", function() error("not found") end)
            require("unreal.health").check()
            local r = find("error", "plenary.nvim not found")
            assert.is_not_nil(r)
            assert.are.equal("required for CompleteMacro", r.hint)
        end)

        it("plenary present -> ok", function()
            h.stub(package.loaded, "plenary", {})
            require("unreal.health").check()
            assert.is_not_nil(find("ok", "plenary.nvim found"))
        end)
    end)
end)
