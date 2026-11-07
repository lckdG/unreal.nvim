local h = dofile("tests/helpers.lua")
local pathUtils = require("unreal.path_utils")

describe("path_utils", function()
    after_each(h.reset)

    describe("GetSourceFilesRoot", function()
        local cases = {
            { "Source/Mod/Public/Foo.h", "Source/Mod" },
            { "Source/Mod/Private/Sub/Foo.cpp", "Source/Mod" },
            { "Source/Mod/Mod.cpp", "Source/Mod" },
            { "Source/Mod/Sub/Foo.cpp", "Source/Mod" },
            { "Source/Top.cpp", "Source" },
            { "Plugins/P/Source/PMod/Public/Foo.h", "Plugins/P/Source/PMod" },
        }
        for _, case in ipairs(cases) do
            it(case[1] .. " -> " .. case[2], function()
                local root = h.project({ [case[1]] = {} })
                h.edit(case[1])
                assert.are.equal(root .. "/" .. case[2], pathUtils.GetSourceFilesRoot())
            end)
        end

        for _, cwd in ipairs({ "Source/Mod/Public", "Source/Mod/Private", "Source/Mod" }) do
            it("cwd = " .. cwd .. " -> Source/Mod", function()
                local root = h.project({ ["Source/Mod/Public/Foo.h"] = {}, ["Source/Mod/Private/Foo.cpp"] = {} })
                vim.cmd.cd(vim.fn.fnameescape(root .. "/" .. cwd))
                h.edit(root .. "/Source/Mod/Public/Foo.h")
                assert.are.equal(root .. "/Source/Mod", pathUtils.GetSourceFilesRoot())
                assert.are.equal(root .. "/Source/Mod/Private/Foo.cpp", pathUtils.GetSourceHeader())
            end)
        end

        it("file outside any Source / Public / Private -> nil without hanging", function()
            h.project({ ["Loose/Foo.cpp"] = {} })
            h.edit("Loose/Foo.cpp")
            assert.is_nil(pathUtils.GetSourceFilesRoot())
            assert.is_nil(pathUtils.GetSourceHeader())
        end)
    end)

    describe("GetSourceHeader", function()
        local PAIR = { "Source/Mod/Public/Foo.h", "Source/Mod/Private/Foo.cpp" }
        for _, case in ipairs({
            { "header -> Private cpp", PAIR, PAIR[1], PAIR[2] },
            { "cpp -> Public header", PAIR, PAIR[2], PAIR[1] },
            {
                "does not match a longer name (MyActor.h from Actor.cpp)",
                { "Source/Mod/Public/MyActor.h", "Source/Mod/Private/Actor.cpp" },
                "Source/Mod/Private/Actor.cpp",
            },
            {
                "does not match another extension (Foo.hpp / Foo.html)",
                { "Source/Mod/Public/Foo.hpp", "Source/Mod/Public/Foo.html", "Source/Mod/Private/Foo.cpp" },
                "Source/Mod/Private/Foo.cpp",
            },
            {
                "handles Lua magic characters in the name (My-Thing)",
                { "Source/Mod/Public/My-Thing.h", "Source/Mod/Private/My-Thing.cpp" },
                "Source/Mod/Private/My-Thing.cpp",
                "Source/Mod/Public/My-Thing.h",
            },
            { "no counterpart -> nil", { "Source/Mod/Private/Foo.cpp" }, "Source/Mod/Private/Foo.cpp" },
            {
                "flat module layout finds the counterpart",
                { "Source/Mod/Foo.h", "Source/Mod/Foo.cpp" },
                "Source/Mod/Foo.h",
                "Source/Mod/Foo.cpp",
            },
            {
                "flat module layout does not pick a same-named file from another module",
                { "Source/Mod/Foo.h", "Source/Other/Foo.cpp" },
                "Source/Mod/Foo.h",
            },
        }) do
            it(case[1], function()
                local tree = {}
                for _, file in ipairs(case[2]) do
                    tree[file] = {}
                end
                local root = h.project(tree)
                h.edit(case[3])
                assert.are.equal(case[4] and vim.fs.joinpath(root, case[4]), pathUtils.GetSourceHeader())
            end)
        end
    end)

    describe("FindUprojects", function()
        before_each(function()
            require("unreal.config").config()
        end)

        it("finds .uproject in subdirectories of cwd", function()
            local root = h.project({ ["Game/Game.uproject"] = {} })
            local found = pathUtils.FindUprojects({ nameOnly = false })
            assert.are.same({ root .. "/Game/Game.uproject" }, found)
        end)

        it("opts.path -> searches that folder, not cwd", function()
            local other = h.tmpdir()
            h.write(other, "Other/Other.uproject")
            h.project({ ["Game/Game.uproject"] = {} })
            local found = pathUtils.FindUprojects({ path = other, nameOnly = false })
            assert.are.same({ other .. "/Other/Other.uproject" }, found)
        end)

        it("nameOnly = true returns basenames", function()
            h.project({ ["Game/Game.uproject"] = {} })
            assert.are.same({ "Game.uproject" }, pathUtils.FindUprojects({ nameOnly = true }))
        end)

        it("opts = nil from a subfolder -> searches the project root", function()
            local root = h.project({ ["Game.uproject"] = {}, ["Source/Game/x.txt"] = {} })
            vim.cmd.cd("Source/Game")
            assert.are.same({ root .. "/Game.uproject" }, pathUtils.FindUprojects())
        end)

        it("stops after uproject_limits files", function()
            require("unreal.config").config({ uproject_limits = 2 })
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {}, ["C/C.uproject"] = {} })
            assert.are.equal(2, #pathUtils.FindUprojects({ nameOnly = true }))
        end)

        it("ignores Foo.uproject.bak", function()
            h.project({ ["Foo.uproject.bak"] = {} })
            assert.are.same({}, pathUtils.FindUprojects({ nameOnly = true }))
        end)
    end)

    describe("Exists", function()
        for _, case in ipairs({
            { "file", "a.txt", true },
            { "missing", "nope", false },
            { "nil", nil, false },
        }) do
            it(case[1] .. " -> " .. tostring(case[3]), function()
                local root = h.project({ ["a.txt"] = {} })
                assert.are.equal(case[3], pathUtils.Exists(case[2] and vim.fs.joinpath(root, case[2])))
            end)
        end
    end)

    describe("BuildConfiguration paths", function()
        local saved

        before_each(function()
            saved = { HOME = vim.env.HOME, APPDATA = vim.env.APPDATA, USERPROFILE = vim.env.USERPROFILE }
            vim.env.HOME = "/home/u"
            vim.env.APPDATA = "C:/Users/u/AppData/Roaming"
            vim.env.USERPROFILE = "C:/Users/u"
        end)

        after_each(function()
            for key, value in pairs(saved) do
                vim.env[key] = value
            end
        end)

        local function on(platform)
            h.stub(require("unreal.system"), "GetPlatform", function()
                return platform
            end)
        end

        local TAIL = "Unreal Engine/UnrealBuildTool/BuildConfiguration.xml"

        it("project file sits next to the uproject", function()
            assert.are.same({
                name = "Project Config",
                value = "/p/Game/Saved/UnrealBuildTool/BuildConfiguration.xml",
            }, pathUtils.GetProjectBuildConfig("/p/Game/Game.uproject"))
        end)

        for _, platform in ipairs({ "Linux", "Mac" }) do
            it(platform .. " -> ~/.config user file", function()
                on(platform)
                assert.are.same(
                    { { name = "User Config", value = "/home/u/.config/" .. TAIL } },
                    pathUtils.GetUserBuildConfig()
                )
            end)
        end

        it("Win64 -> AppData and Documents user files", function()
            on("Win64")
            assert.are.same({
                { name = "User AppData Config", value = "C:/Users/u/AppData/Roaming/" .. TAIL },
                { name = "User Document Config", value = "C:/Users/u/Documents/" .. TAIL },
            }, pathUtils.GetUserBuildConfig())
        end)

        it("unknown platform -> nil", function()
            on("Unknown")
            assert.is_nil(pathUtils.GetUserBuildConfig())
        end)
    end)
end)
