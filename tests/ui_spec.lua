local h = dofile("tests/helpers.lua")
local ui = require("unreal.ui")

describe("ui", function()
    after_each(h.reset)

    describe("SelectOptionsCb", function()
        local cases = {
            { 2, "b" },
            { 0, nil },
            { 9, nil },
            { -1, nil },
        }
        for _, case in ipairs(cases) do
            it("inputlist returns " .. case[1], function()
                h.stub(vim.fn, "inputlist", function() return case[1] end)
                local got = {}
                ui.SelectOptionsCb("Pick", { "a", "b" }, function(opt) table.insert(got, opt) end)
                assert.are.same(case[2] and { case[2] } or {}, got)
            end)
        end
    end)

    it("SelectOptions numbers the options", function()
        local calls = h.spy(vim.fn, "inputlist", 1)
        ui.SelectOptions("Pick", { "a", "b" })
        assert.are.same({ "Pick", "1: a", "2: b" }, calls[1][1])
    end)
end)
