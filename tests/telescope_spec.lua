local h = dofile("tests/helpers.lua")
local telescope = require("unreal.extensions.telescope")
local ui = require("unreal.ui")

local fake_modules = {
    "telescope",
    "telescope.config",
    "telescope.builtin",
    "telescope.pickers",
    "telescope.finders",
    "telescope.previewers",
    "telescope.actions",
    "telescope.actions.state",
}

local function fake_telescope(existing)
    local calls = {}
    package.loaded["telescope"] = {}
    local values = {
        file_ignore_patterns = existing,
        generic_sorter = function()
            return {}
        end,
    }
    package.loaded["telescope.config"] = {
        values = values,
        -- like telescope, applied defaults show up in `values`
        set_defaults = function(...)
            table.insert(calls, { ... })
            values.file_ignore_patterns = (...).file_ignore_patterns
        end,
    }
    return calls
end

describe("extensions.telescope", function()
    before_each(function()
        h.stub(ui, "provider", ui.provider)
    end)

    after_each(function()
        h.reset()
        for _, name in ipairs(fake_modules) do
            package.loaded[name] = nil
        end
    end)

    describe("AppendIgnorePatterns", function()
        it("appends to the user's patterns", function()
            local calls = fake_telescope({ "user%.txt" })
            telescope.AppendIgnorePatterns({ "%.uasset" })
            assert.are.same({ "user%.txt", "%.uasset" }, calls[1][1].file_ignore_patterns)
        end)

        it("nil ignores -> defaults untouched", function()
            local calls = fake_telescope({ "user%.txt" })
            telescope.AppendIgnorePatterns(nil)
            assert.are.equal(0, #calls)
        end)

        it("called twice -> patterns appended once", function()
            local calls = fake_telescope({ "user%.txt" })
            telescope.AppendIgnorePatterns({ "%.uasset" })
            telescope.AppendIgnorePatterns({ "%.uasset" })
            assert.are.equal(1, #calls)
            assert.are.same({ "user%.txt", "%.uasset" }, calls[1][1].file_ignore_patterns)
        end)
    end)

    describe("setup", function()
        it("becomes the ui provider and applies ignores", function()
            local calls = fake_telescope({})
            telescope.setup({ ignores = { "%.uasset" } })
            assert.are.equal(telescope, ui.provider)
            assert.are.same({ "%.uasset" }, calls[1][1].file_ignore_patterns)
        end)

        it("without ignores -> still becomes the ui provider", function()
            fake_telescope({})
            telescope.setup({})
            assert.are.equal(telescope, ui.provider)
        end)

        it("telescope not installed -> error notify, provider unchanged", function()
            local before = ui.provider
            local notes = h.notifications()
            h.stub(package.preload, "telescope", function()
                error("not found")
            end)
            assert.has_no.errors(function()
                telescope.setup({ ignores = { "%.uasset" } })
            end)
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
            assert.are.equal(before, ui.provider)
        end)
    end)

    describe("as provider", function()
        local finds, greps

        before_each(function()
            fake_telescope({})
            finds, greps = {}, {}
            package.loaded["telescope.builtin"] = {
                find_files = function(o)
                    table.insert(finds, o)
                end,
                live_grep = function(o)
                    table.insert(greps, o)
                end,
            }
            telescope.setup({})
        end)

        it("FindSource / GrepSource args reach telescope.builtin", function()
            ui.FileSearch({ "rg", "--files", "-g", "*.h" }, { prompt = "Find" })
            ui.GrepSearch({ "rg", "--vimgrep", "-S", "-g", "*.h" }, { prompt = "Grep" })
            assert.are.same({ { prompt_title = "Find", find_command = { "rg", "--files", "-g", "*.h" } } }, finds)
            assert.are.same({ { prompt_title = "Grep", additional_args = { "-g", "*.h" } } }, greps)
        end)

        it("Input stays on vim.ui.input", function()
            local calls = h.spy(vim.ui, "input")
            ui.Input({ prompt = "Path: " }, function() end)
            assert.are.equal(1, #calls)
            assert.are.equal("Path: ", calls[1][1].prompt)
        end)
    end)

    describe("Select", function()
        local spec, selected, replaced

        before_each(function()
            fake_telescope({})
            spec, selected, replaced = nil, nil, nil
            package.loaded["telescope.pickers"] = {
                new = function(_, s)
                    spec = s
                    return { find = function() end }
                end,
            }
            package.loaded["telescope.finders"] = {
                new_table = function(t)
                    return t
                end,
            }
            package.loaded["telescope.previewers"] = {
                new_buffer_previewer = function(o)
                    return o
                end,
            }
            package.loaded["telescope.actions"] = {
                close = function() end,
                select_default = {
                    replace = function(_, fn)
                        replaced = fn
                    end,
                },
            }
            package.loaded["telescope.actions.state"] = {
                get_selected_entry = function()
                    return selected
                end,
            }
        end)

        local function pick(items, index)
            local got = "unset"
            telescope.Select(items, { prompt = "Pick" }, function(entry)
                got = entry
            end)
            spec.attach_mappings(1)
            selected = index and spec.finder.entry_maker(items[index]) or nil
            replaced()
            return got
        end

        it("returns the original entry, shows name", function()
            local items = ui.WrapList({ "a", "b" })
            local got = pick(items, 2)
            assert.are.equal(items[2], got)
            assert.are.equal("Pick", spec.prompt_title)
            assert.are.equal("b", spec.finder.entry_maker(items[2]).display)
        end)

        it("nothing selected -> cb(nil)", function()
            assert.is_nil(pick(ui.WrapList({ "a" }), nil))
        end)

        it("entries without doc lines (WrapList) -> no previewer", function()
            pick(ui.WrapList({ "a" }), 1)
            assert.is_nil(spec.previewer)
        end)

        it("entries with doc lines -> previewer shows them", function()
            local items = { { name = "UP::EditAnywhere", value = {}, desc = { "line 1", "line 2" } } }
            pick(items, 1)
            assert.is_not_nil(spec.previewer)
            local bufnr = vim.api.nvim_create_buf(false, true)
            spec.previewer.define_preview({ state = { bufnr = bufnr } }, spec.finder.entry_maker(items[1]))
            assert.are.same({ "line 1", "line 2" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        end)
    end)
end)
