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

        it("not found, clangd attached -> LspClangdSwitchSourceHeader", function()
            h.stub(pathUtils, "GetSourceHeader", function()
                return nil
            end)
            h.stub(system, "HasClangdEnabled", function()
                return true
            end)
            capture_cmd()
            search.SwitchSourceHeader()
            assert.are.same({ "LspClangdSwitchSourceHeader" }, cmds)
        end)

        it("not found, no clangd -> error notify", function()
            h.stub(pathUtils, "GetSourceHeader", function()
                return nil
            end)
            h.stub(system, "HasClangdEnabled", function()
                return false
            end)
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

    describe("telescope provider", function()
        local telescope = require("unreal.extensions.telescope")
        local finds, greps

        before_each(function()
            finds, greps = {}, {}
            package.loaded["telescope.builtin"] = {
                find_files = function(o)
                    table.insert(finds, o)
                end,
                live_grep = function(o)
                    table.insert(greps, o)
                end,
            }
        end)
        after_each(function()
            package.loaded["telescope.builtin"] = nil
        end)

        it("FileSearch -> find_files with the rg command", function()
            telescope.FileSearch({ "rg", "--files", "-g", "*.h" }, { prompt = "Find" })
            assert.are.same({ { prompt_title = "Find", find_command = { "rg", "--files", "-g", "*.h" } } }, finds)
        end)

        it("GrepSearch -> live_grep with only the glob args", function()
            telescope.GrepSearch({ "rg", "--vimgrep", "-S", "-g", "*.h" }, { prompt = "Grep" })
            assert.are.same({ { prompt_title = "Grep", additional_args = { "-g", "*.h" } } }, greps)
        end)
    end)
end)
