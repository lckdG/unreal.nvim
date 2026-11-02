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
        it("header -> Private cpp", function()
            h.project({ ["Source/Mod/Public/Foo.h"] = {}, ["Source/Mod/Private/Foo.cpp"] = {} })
            h.edit("Source/Mod/Public/Foo.h")
            assert.is_true(h.ends_with(pathUtils.GetSourceHeader(), "Source/Mod/Private/Foo.cpp"))
        end)

        it("cpp -> Public header", function()
            h.project({ ["Source/Mod/Public/Foo.h"] = {}, ["Source/Mod/Private/Foo.cpp"] = {} })
            h.edit("Source/Mod/Private/Foo.cpp")
            assert.is_true(h.ends_with(pathUtils.GetSourceHeader(), "Source/Mod/Public/Foo.h"))
        end)

        it("does not match a longer name (MyActor.h from Actor.cpp)", function()
            h.project({ ["Source/Mod/Public/MyActor.h"] = {}, ["Source/Mod/Private/Actor.cpp"] = {} })
            h.edit("Source/Mod/Private/Actor.cpp")
            assert.is_nil(pathUtils.GetSourceHeader())
        end)

        it("does not match another extension (Foo.hpp / Foo.html)", function()
            h.project({
                ["Source/Mod/Public/Foo.hpp"] = {},
                ["Source/Mod/Public/Foo.html"] = {},
                ["Source/Mod/Private/Foo.cpp"] = {},
            })
            h.edit("Source/Mod/Private/Foo.cpp")
            assert.is_nil(pathUtils.GetSourceHeader())
        end)

        it("handles Lua magic characters in the name (My-Thing)", function()
            h.project({ ["Source/Mod/Public/My-Thing.h"] = {}, ["Source/Mod/Private/My-Thing.cpp"] = {} })
            h.edit("Source/Mod/Private/My-Thing.cpp")
            assert.is_true(h.ends_with(pathUtils.GetSourceHeader(), "Source/Mod/Public/My-Thing.h"))
        end)

        it("no counterpart -> nil", function()
            h.project({ ["Source/Mod/Private/Foo.cpp"] = {} })
            h.edit("Source/Mod/Private/Foo.cpp")
            assert.is_nil(pathUtils.GetSourceHeader())
        end)

        it("flat module layout finds the counterpart", function()
            h.project({ ["Source/Mod/Foo.h"] = {}, ["Source/Mod/Foo.cpp"] = {} })
            h.edit("Source/Mod/Foo.h")
            assert.is_true(h.ends_with(pathUtils.GetSourceHeader(), "Source/Mod/Foo.cpp"))
        end)

        it("flat module layout does not pick a same-named file from another module", function()
            h.project({ ["Source/Mod/Foo.h"] = {}, ["Source/Other/Foo.cpp"] = {} })
            h.edit("Source/Mod/Foo.h")
            assert.is_nil(pathUtils.GetSourceHeader())
        end)
    end)

    describe("FindUprojects", function()
        it("upward = false finds .uproject in subdirectories", function()
            local root = h.project({ ["Game/Game.uproject"] = {} })
            local found = pathUtils.FindUprojects({ upward = false, nameOnly = false })
            assert.are.same({ root .. "/Game/Game.uproject" }, found)
        end)

        it("upward = true finds .uproject in parent directories", function()
            local root = h.project({ ["Game.uproject"] = {}, ["Source/Game/x.txt"] = {} })
            vim.cmd.cd("Source/Game")
            local found = pathUtils.FindUprojects({ upward = true, nameOnly = false })
            assert.are.same({ root .. "/Game.uproject" }, found)
        end)

        it("nameOnly = true returns basenames", function()
            h.project({ ["Game/Game.uproject"] = {} })
            assert.are.same({ "Game.uproject" }, pathUtils.FindUprojects({ upward = false, nameOnly = true }))
        end)

        it("opts = nil searches downward with full paths", function()
            local root = h.project({ ["Game/Game.uproject"] = {} })
            assert.are.same({ root .. "/Game/Game.uproject" }, pathUtils.FindUprojects())
        end)

        it("ignores Foo.uproject.bak", function()
            h.project({ ["Foo.uproject.bak"] = {} })
            assert.are.same({}, pathUtils.FindUprojects({ upward = false, nameOnly = true }))
        end)
    end)

    describe("Exists", function()
        it("file -> true", function()
            local root = h.project({ ["a.txt"] = {} })
            assert.is_true(pathUtils.Exists(root .. "/a.txt"))
        end)

        it("directory -> true", function()
            assert.is_true(pathUtils.Exists(h.tmpdir()))
        end)

        it("missing -> false", function()
            assert.is_false(pathUtils.Exists(h.tmpdir() .. "/nope"))
        end)
    end)

    describe("ToIgnoreDirPattern", function()
        local slash = package.config:sub(1, 1)
        local cases = {
            { "Binaries/Linux/x", true },
            { "Plugins/Foo/Binaries/x", true },
            { "/abs/Project/Binaries/x", true },
            { "Source/MyBuild/x.cpp", false },
            { "Source/My_Build/x.cpp", false },
            { "Source/Build.cs", false },
            { "Source/Binaries.cpp", false },
        }
        for _, case in ipairs(cases) do
            it("Binaries/Build: " .. case[1] .. " -> " .. (case[2] and "ignored" or "kept"), function()
                local path = case[1]:gsub("/", slash)
                local ignored = path:find(pathUtils.ToIgnoreDirPattern("Binaries")) ~= nil
                    or path:find(pathUtils.ToIgnoreDirPattern("Build")) ~= nil
                assert.are.equal(case[2], ignored)
            end)
        end
    end)
end)
