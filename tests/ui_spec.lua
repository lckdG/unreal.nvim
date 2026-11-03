local h = dofile("tests/helpers.lua")
local ui = require("unreal.ui")

describe("ui", function()
    local native

    before_each(function()
        -- Use(nil) falls back to the native provider; grab it, then restore after the test
        h.stub(ui, "provider", ui.provider)
        ui.Use(nil)
        native = ui.provider
    end)
    after_each(h.reset)

    describe("Use", function()
        it("custom provider -> calls go to it", function()
            local calls = {}
            ui.Use({
                Select = function(...)
                    table.insert(calls, { "Select", ... })
                end,
                Input = function(...)
                    table.insert(calls, { "Input", ... })
                end,
                FileSearch = function(...)
                    table.insert(calls, { "FileSearch", ... })
                end,
                GrepSearch = function(...)
                    table.insert(calls, { "GrepSearch", ... })
                end,
            })
            ui.Select({}, {}, function() end)
            ui.Input({}, function() end)
            ui.FileSearch({}, {})
            ui.GrepSearch({}, {})
            assert.are.same(
                { "Select", "Input", "FileSearch", "GrepSearch" },
                vim.tbl_map(function(c)
                    return c[1]
                end, calls)
            )
        end)

        it("nil -> native provider", function()
            ui.Use({})
            ui.Use(nil)
            assert.are.equal(native, ui.provider)
        end)
    end)

    describe("native Select", function()
        it("passes prompt, formats by name, returns the chosen entry", function()
            local seen
            h.stub(vim.ui, "select", function(items, opts, cb)
                seen = { prompt = opts.prompt, label = opts.format_item(items[2]) }
                cb(items[2])
            end)
            local got
            ui.Select(ui.WrapList({ "a", "b" }), { prompt = "Pick" }, function(entry)
                got = entry
            end)
            assert.are.same({ prompt = "Pick", label = "b" }, seen)
            assert.are.same({ name = "b", value = "b", desc = "" }, got)
        end)

        it("cancel -> cb(nil)", function()
            h.stub(vim.ui, "select", function(_, _, cb)
                cb(nil)
            end)
            local called, got = false, "unset"
            ui.Select(ui.WrapList({ "a" }), {}, function(entry)
                called, got = true, entry
            end)
            assert.is_true(called)
            assert.is_nil(got)
        end)
    end)

    it("native Input uses vim.ui.input overridden after load", function()
        local calls = h.spy(vim.ui, "input")
        ui.Input({ prompt = "Path: " }, function() end)
        assert.are.equal(1, #calls)
        assert.are.equal("Path: ", calls[1][1].prompt)
    end)

    describe("WrapList", function()
        it("value = item", function()
            assert.are.same({
                { name = "a", value = "a", desc = "" },
                { name = "b", value = "b", desc = "" },
            }, ui.WrapList({ "a", "b" }))
        end)

        it("indexAsValue -> value = index", function()
            assert.are.same({
                { name = "a", value = 1, desc = "" },
                { name = "b", value = 2, desc = "" },
            }, ui.WrapList({ "a", "b" }, true))
        end)

        it("empty -> empty", function()
            assert.are.same({}, ui.WrapList({}))
        end)
    end)
end)
