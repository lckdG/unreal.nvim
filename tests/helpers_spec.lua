local h = dofile("tests/helpers.lua")
local helpers = require("unreal.helpers")

describe("helpers", function()
    after_each(h.reset)

    describe("module table", function()
        for _, name in ipairs({ "path", "list", "buffer", "log" }) do
            it(name .. " -> same table as require", function()
                assert.are.equal(require("unreal.helpers." .. name), helpers[name])
            end)
        end

        it("unknown helper -> error", function()
            assert.has_error(function()
                return helpers.nope
            end)
        end)
    end)

    describe("path.Exists", function()
        for _, case in ipairs({
            { "file", "a.txt", true },
            { "folder", "sub", true },
            { "missing", "nope", false },
            { "nil", nil, false },
        }) do
            it(case[1] .. " -> " .. tostring(case[3]), function()
                local root = h.project({ ["a.txt"] = {}, ["sub/b.txt"] = {} })
                assert.are.equal(case[3], helpers.path.Exists(case[2] and vim.fs.joinpath(root, case[2])))
            end)
        end
    end)

    describe("list.StrContains", function()
        for _, case in ipairs({
            { "exact match", { "Foo", "Bar" }, "Bar", true, true },
            { "other case, matchCase", { "Foo" }, "foo", true, false },
            { "other case, no matchCase", { "Foo" }, "foo", false, true },
            { "missing", { "Foo" }, "Baz", false, false },
            { "empty list", {}, "Foo", false, false },
        }) do
            it(case[1] .. " -> " .. tostring(case[5]), function()
                assert.are.equal(case[5], helpers.list.StrContains(case[2], case[3], case[4]))
            end)
        end

        it("list not a table -> error", function()
            assert.has_error(function()
                helpers.list.StrContains(nil, "Foo", true)
            end)
        end)
    end)

    describe("buffer", function()
        it("CreateTemp -> unlisted scratch buffer with a name", function()
            local buf = helpers.buffer.CreateTemp()
            assert.is_true(vim.api.nvim_buf_is_valid(buf))
            assert.is_false(vim.bo[buf].buflisted)
            assert.are.equal("nofile", vim.bo[buf].buftype)
            assert.are_not.equal("", vim.api.nvim_buf_get_name(buf))
        end)

        it("CreateTemp twice -> different buffers and names", function()
            local a, b = helpers.buffer.CreateTemp(), helpers.buffer.CreateTemp()
            assert.are_not.equal(a, b)
            assert.are_not.equal(vim.api.nvim_buf_get_name(a), vim.api.nvim_buf_get_name(b))
        end)

        it("OpenBuffer new file -> loaded with file content", function()
            local root = h.project({})
            local file = h.write(root, "Foo.cpp", { "int x;" })
            local buf = helpers.buffer.OpenBuffer(file)
            assert.is_true(vim.api.nvim_buf_is_loaded(buf))
            assert.are.same({ "int x;" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        end)

        it("OpenBuffer already open -> same buffer", function()
            local root = h.project({ ["Foo.cpp"] = {} })
            vim.cmd.edit(vim.fs.joinpath(root, "Foo.cpp"))
            local open = vim.api.nvim_get_current_buf()
            assert.are.equal(open, helpers.buffer.OpenBuffer(vim.fs.joinpath(root, "Foo.cpp")))
        end)
    end)

    describe("log", function()
        local notes

        before_each(function()
            notes = h.notifications()
            h.stub(helpers.log, "LogPrefix", helpers.log.LogPrefix)
        end)

        it("init -> prefix from plugin name", function()
            helpers.log.init({ PluginName = "unreal.nvim" })
            assert.are.equal("[unreal.nvim] ", helpers.log.LogPrefix)
        end)

        it("Notify -> prefixed message, level kept", function()
            helpers.log.init({ PluginName = "X" })
            helpers.log.Notify("hello", vim.log.levels.WARN)
            assert.are.same({ { msg = "[X] hello", level = vim.log.levels.WARN } }, notes)
        end)
    end)
end)
