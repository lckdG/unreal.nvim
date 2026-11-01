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
        h.stub(vim, "cmd", function(c) table.insert(cmds, c) end)
    end

    describe("SwitchSourceHeader", function()
        it("counterpart path with special chars is escaped for :edit", function()
            -- space, '#' and '%' would break an unescaped :e
            h.project({ ["Source/My Mod #1/Foo%.h"] = {}, ["Source/My Mod #1/Foo%.cpp"] = {} })
            h.edit("Source/My Mod #1/Foo%.h")
            search.SwitchSourceHeader()
            assert.is_true(h.ends_with(vim.api.nvim_buf_get_name(0), "Source/My Mod #1/Foo%.cpp"))
        end)

        it("not found, clangd attached -> LspClangdSwitchSourceHeader", function()
            h.stub(pathUtils, "GetSourceHeader", function() return nil end)
            h.stub(system, "HasClangdEnabled", function() return true end)
            capture_cmd()
            search.SwitchSourceHeader()
            assert.are.same({ "LspClangdSwitchSourceHeader" }, cmds)
        end)

        it("not found, no clangd -> error notify", function()
            h.stub(pathUtils, "GetSourceHeader", function() return nil end)
            h.stub(system, "HasClangdEnabled", function() return false end)
            capture_cmd()
            search.SwitchSourceHeader()
            assert.are.same({}, cmds)
            assert.is_true(h.notified(notes, "No matching file name or clangd enabled!", vim.log.levels.ERROR))
        end)

        it("HasClangdEnabled only looks at the current buffer", function()
            local calls = h.spy(vim.lsp, "get_clients", {})
            assert.is_false(system.HasClangdEnabled())
            assert.are.same({ name = "clangd", bufnr = 0 }, calls[1][1])
        end)

        it("flat module layout opens the counterpart", function()
            h.project({ ["Source/Mod/Foo.h"] = {}, ["Source/Mod/Foo.cpp"] = {} })
            h.edit("Source/Mod/Foo.h")
            search.SwitchSourceHeader()
            assert.is_true(h.ends_with(vim.api.nvim_buf_get_name(0), "Source/Mod/Foo.cpp"))
        end)
    end)

    describe("FindSource / GrepSource", function()
        local finds, greps

        before_each(function()
            finds, greps = {}, {}
            package.loaded["telescope.builtin"] = {
                find_files = function(o) table.insert(finds, o) end,
                live_grep = function(o) table.insert(greps, o) end,
            }
        end)
        after_each(function()
            package.loaded["telescope.builtin"] = nil
        end)

        local cases = { { 1, "*.{h,cpp}" }, { 2, "*.h" }, { 3, "*.cpp" } }
        for _, case in ipairs(cases) do
            it("choice " .. case[1] .. " -> -g " .. case[2], function()
                h.stub(vim.fn, "inputlist", function() return case[1] end)
                search.FindSource()
                search.GrepSource()
                assert.are.same({ "rg", "--files", "-g", case[2] }, finds[1].find_command)
                assert.are.same({ "-g", case[2] }, greps[1].additional_args)
            end)
        end

        for _, choice in ipairs({ 0, 4 }) do
            it("choice " .. choice .. " -> warn, telescope not called", function()
                h.stub(vim.fn, "inputlist", function() return choice end)
                search.FindSource()
                search.GrepSource()
                assert.are.equal(0, #finds + #greps)
                assert.is_true(h.notified(notes, "Invalid search choice", vim.log.levels.WARN))
            end)
        end
    end)
end)
