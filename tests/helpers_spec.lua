local h = dofile("tests/helpers.lua")
local helpers = require("unreal.helpers")

describe("helpers", function()
    after_each(h.reset)

    describe("module table", function()
        for _, name in ipairs({ "path", "list", "buffer", "log", "xml" }) do
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

    describe("xml.GetTagContent", function()
        local function xml(lines)
            return h.write(h.project({}), "CrashContext.runtime-xml", lines)
        end

        it("several tags -> lines of each, trimmed and decoded", function()
            local file = xml({
                "<Root>",
                "\t\t<CrashType>Ensure</CrashType>",
                "\t\t<ErrorMessage>Ensure failed: a &lt; b &amp;&amp; c",
                "  second line  ",
                "</ErrorMessage>",
                "</Root>",
            })
            assert.are.same({
                CrashType = { "Ensure" },
                ErrorMessage = { "Ensure failed: a < b && c", "second line" },
            }, helpers.xml.GetTagContent(file, { "CrashType", "ErrorMessage" }))
        end)

        it("&amp;lt; -> &lt;, not <", function()
            local file = xml({ "<A>&amp;lt;</A>" })
            assert.are.same({ A = { "&lt;" } }, helpers.xml.GetTagContent(file, { "A" }))
        end)

        it("missing tag -> no key", function()
            local file = xml({ "<A>x</A>" })
            assert.are.same({ A = { "x" } }, helpers.xml.GetTagContent(file, { "A", "B" }))
        end)

        it("tag with pattern characters -> matched literally", function()
            local file = xml({ "<AxB>wrong</AxB>", "<A.B-C>right</A.B-C>" })
            assert.are.same({ ["A.B-C"] = { "right" } }, helpers.xml.GetTagContent(file, { "A.B-C" }))
        end)

        it("missing file -> empty", function()
            assert.are.same({}, helpers.xml.GetTagContent(h.tmpdir() .. "/nope.xml", { "A" }))
        end)
    end)

    describe("xml.ParseCallStack", function()
        local function crash(frames)
            local lines = { "<Root>" }
            vim.list_extend(lines, frames)
            table.insert(lines, "</Root>")
            return h.write(h.project({}), "CrashContext.runtime-xml", lines)
        end

        it("frame with source -> filename, number lnum, Module!Function text", function()
            local file = crash({ "<CallStack>Lib.so!AFoo::Bar() [/ue/Source/Foo.cpp:42]", "</CallStack>" })
            assert.are.same(
                { { filename = "/ue/Source/Foo.cpp", lnum = 42, text = "Lib.so!AFoo::Bar()" } },
                helpers.xml.ParseCallStack(file)
            )
        end)

        it("frame without source -> text only", function()
            local file = crash({ "<CallStack>libc.so.6!__libc_start_main(+0x88)", "</CallStack>" })
            assert.are.same({ { text = "libc.so.6!__libc_start_main(+0x88)" } }, helpers.xml.ParseCallStack(file))
        end)

        it("/./ in the path -> removed", function()
            local file = crash({ "<CallStack>M!F() [/ue/Source/./Editor/Foo.cpp:1]</CallStack>" })
            assert.are.equal("/ue/Source/Editor/Foo.cpp", helpers.xml.ParseCallStack(file)[1].filename)
        end)

        it("Windows path with drive and spaces -> split at the last colon", function()
            local file = crash({ "<CallStack>M!F() [C:\\My Proj\\Source\\Foo.cpp:7]</CallStack>" })
            local item = helpers.xml.ParseCallStack(file)[1]
            assert.are.equal(vim.fs.normalize("C:\\My Proj\\Source\\Foo.cpp"), item.filename)
            assert.are.equal(7, item.lnum)
        end)

        it("escaped templates and brackets in the function -> decoded, source still found", function()
            local file = crash({
                "<CallStack>M!TArray&lt;int&gt;::operator[](int) const&amp; [/ue/Array.h:9]</CallStack>",
            })
            assert.are.same(
                { { filename = "/ue/Array.h", lnum = 9, text = "M!TArray<int>::operator[](int) const&" } },
                helpers.xml.ParseCallStack(file)
            )
        end)

        it("frames keep their order", function()
            local file = crash({ "<CallStack>A!a() [/a.cpp:1]", "B!b(+0x1)", "C!c() [/c.cpp:3]", "</CallStack>" })
            assert.are.same(
                { "A!a()", "B!b(+0x1)", "C!c()" },
                vim.tbl_map(function(item)
                    return item.text
                end, helpers.xml.ParseCallStack(file))
            )
        end)

        it("no CallStack -> nil", function()
            assert.is_nil(helpers.xml.ParseCallStack(crash({ "<CrashType>Ensure</CrashType>" })))
        end)

        it("missing file -> nil", function()
            assert.is_nil(helpers.xml.ParseCallStack(h.tmpdir() .. "/nope.xml"))
        end)
    end)
end)
