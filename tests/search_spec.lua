local h = dofile("tests/helpers.lua")
local search = require("unreal.search")
local pathUtils = require("unreal.path_utils")
local system = require("unreal.system")

describe("search", function()
    local notes, cmds

    before_each(function()
        notes = h.notifications()
        cmds = {}
    end)
    after_each(h.reset)

    local function capture_cmd()
        h.stub(vim, "cmd", function(c)
            table.insert(cmds, c)
        end)
    end

    describe("SwitchSourceHeader", function()
        it("counterpart path with special chars is escaped for :edit", function()
            h.project({ ["Source/My Mod #1/Foo%.h"] = {}, ["Source/My Mod #1/Foo%.cpp"] = {} })
            h.edit("Source/My Mod #1/Foo%.h")
            search.SwitchSourceHeader()
            assert.is_true(h.ends_with(vim.api.nvim_buf_get_name(0), "Source/My Mod #1/Foo%.cpp"))
        end)

        it("not found -> falls back to clangd switchSourceHeader", function()
            h.stub(pathUtils, "GetSourceHeader", function()
                return nil
            end)
            local switches = h.spy(require("unreal.lsp"), "SwitchSourceHeader")
            capture_cmd()
            search.SwitchSourceHeader()
            assert.are.equal(1, #switches)
            assert.are.same({}, cmds)
        end)

        it("found -> clangd not asked", function()
            h.project({ ["Source/Mod/Foo.h"] = {}, ["Source/Mod/Foo.cpp"] = {} })
            h.edit("Source/Mod/Foo.h")
            local switches = h.spy(require("unreal.lsp"), "SwitchSourceHeader")
            search.SwitchSourceHeader()
            assert.are.equal(0, #switches)
        end)

        it("HasClangdEnabled only looks at the current buffer", function()
            local calls = h.spy(vim.lsp, "get_clients", {})
            assert.is_false(system.HasClangdEnabled())
            assert.are.same({ name = "clangd", bufnr = 0 }, calls[1][1])
        end)
    end)

    describe("FindSource / GrepSource", function()
        local ui = require("unreal.ui")
        local finds, greps

        before_each(function()
            finds = h.spy(ui, "FileSearch")
            greps = h.spy(ui, "GrepSearch")
        end)

        local function choose(name)
            h.stub(ui, "Select", function(items, _, cb)
                for _, item in ipairs(items) do
                    if item.name == name then
                        return cb(item)
                    end
                end
                cb(nil)
            end)
        end

        local SCOPES = {
            { "All", { "-g", "*.{h,cpp}" } },
            { "Headers", { "-g", "*.h" } },
            { "Cpp", { "-g", "*.cpp" } },
            {
                "Ini",
                {
                    "--no-ignore",
                    "-g",
                    "!Intermediate/",
                    "-g",
                    "!Binaries/",
                    "-g",
                    "!CrashReportClient/",
                    "-g",
                    "*.ini",
                },
            },
            { "Build Files", { "-g", "*.{Build,Target}.cs" } },
        }

        for _, case in ipairs(SCOPES) do
            it("choice " .. case[1] .. " -> " .. table.concat(case[2], " "), function()
                choose(case[1])
                search.FindSource()
                search.GrepSource()
                assert.are.same(vim.list_extend({ "rg", "--files" }, case[2]), finds[1][1])
                assert.are.same(vim.list_extend({ "rg", "--vimgrep", "-S" }, case[2]), greps[1][1])
            end)
        end

        it("prompt lists every scope", function()
            local names = {}
            h.stub(ui, "Select", function(items)
                names = vim.tbl_map(function(item)
                    return item.name
                end, items)
            end)
            search.FindSource()
            assert.are.same(
                vim.tbl_map(function(case)
                    return case[1]
                end, SCOPES),
                names
            )
        end)

        it("cancelled -> no search", function()
            choose(nil)
            search.FindSource()
            search.GrepSource()
            assert.are.equal(0, #finds + #greps)
        end)
    end)

    if vim.fn.executable("rg") == 1 then
        describe("real rg, native provider", function()
            local ui = require("unreal.ui")
            local qf

            before_each(function()
                qf = nil
                ui.Use(nil)
                h.stub(vim.fn, "setqflist", function(_, _, what)
                    qf = what
                end)
                h.stub(vim.cmd, "copen", function() end)
            end)

            local function run(fn, scope, typed)
                h.stub(ui, "Select", function(items, _, cb)
                    for _, item in ipairs(items) do
                        if item.name == scope then
                            return cb(item)
                        end
                    end
                end)
                h.stub(vim.ui, "input", function(_, cb)
                    cb(typed)
                end)
                fn()
                assert.is_true(vim.wait(5000, function()
                    return qf ~= nil
                end))
                local lines = qf.lines
                table.sort(lines)
                return lines
            end

            local iniTree = {
                [".ignore"] = { "Saved/" },
                ["Config/DefaultEngine.ini"] = { "[/Script/Engine]" },
                ["Saved/Config/Linux/Game.ini"] = { "[/Script/Engine]" },
                ["Plugins/P/Config/DefaultP.ini"] = { "[/Script/Engine]" },
                ["Intermediate/Config/CoalescedSourceConfigs/E.ini"] = { "[/Script/Engine]" },
                ["Binaries/Linux/x.ini"] = { "[/Script/Engine]" },
                ["Plugins/P/Intermediate/a.ini"] = { "[/Script/Engine]" },
                ["Saved/CrashReportClient/c.ini"] = { "[/Script/Engine]" },
                ["Source/Game/Game.h"] = { "[/Script/Engine]" },
            }

            it("Ini files: ignored Saved/ included, generated dirs excluded", function()
                h.project(iniTree)
                assert.are.same({
                    "Config/DefaultEngine.ini",
                    "Plugins/P/Config/DefaultP.ini",
                    "Saved/Config/Linux/Game.ini",
                }, run(search.FindSource, "Ini", ""))
            end)

            it("Ini files: typed text narrows by name", function()
                h.project(iniTree)
                assert.are.same({ "Saved/Config/Linux/Game.ini" }, run(search.FindSource, "Ini", "Game"))
            end)

            it("Ini grep: same files, matches carry line and column", function()
                h.project(iniTree)
                assert.are.same({
                    "Config/DefaultEngine.ini:1:2:[/Script/Engine]",
                    "Plugins/P/Config/DefaultP.ini:1:2:[/Script/Engine]",
                    "Saved/Config/Linux/Game.ini:1:2:[/Script/Engine]",
                }, run(search.GrepSource, "Ini", "/Script"))
            end)

            local buildTree = {
                ["Source/Game/Game.Build.cs"] = {},
                ["Source/Game.Target.cs"] = {},
                ["Source/GameEditor.Target.cs"] = {},
                ["Plugins/P/Source/P/P.Build.cs"] = {},
                ["Source/Game/Foo.cs"] = {},
                ["Source/Game/Game.h"] = {},
            }

            it("Build Files: every Build.cs and Target.cs, nothing else", function()
                h.project(buildTree)
                assert.are.same({
                    "Plugins/P/Source/P/P.Build.cs",
                    "Source/Game.Target.cs",
                    "Source/Game/Game.Build.cs",
                    "Source/GameEditor.Target.cs",
                }, run(search.FindSource, "Build Files", ""))
            end)

            it("Build Files: typed text narrows across both suffixes", function()
                h.project(buildTree)
                assert.are.same({ "Source/GameEditor.Target.cs" }, run(search.FindSource, "Build Files", "Editor"))
                qf = nil
                assert.are.same(
                    { "Source/Game.Target.cs", "Source/Game/Game.Build.cs", "Source/GameEditor.Target.cs" },
                    run(search.FindSource, "Build Files", "Game")
                )
            end)
        end)
    else
        pending("real rg, native provider: rg not installed")
    end
end)
