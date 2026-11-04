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
            -- space, '#' and '%' would break an unescaped :e
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

        local cases = { { "All", "*.{h,cpp}" }, { "Headers", "*.h" }, { "Cpp", "*.cpp" } }
        for _, case in ipairs(cases) do
            it("choice " .. case[1] .. " -> -g " .. case[2], function()
                choose(case[1])
                search.FindSource()
                search.GrepSource()
                assert.are.same({ "rg", "--files", "-g", case[2] }, finds[1][1])
                assert.are.same({ "rg", "--vimgrep", "-S", "-g", case[2] }, greps[1][1])
            end)
        end

        it("cancelled -> no search", function()
            choose(nil)
            search.FindSource()
            search.GrepSource()
            assert.are.equal(0, #finds + #greps)
        end)
    end)
end)
