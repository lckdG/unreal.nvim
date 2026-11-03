local h = dofile("tests/helpers.lua")

local function read(rel)
    return table.concat(vim.fn.readfile(vim.fs.joinpath(h.repo_root, rel)), "\n")
end

describe("help file", function()
    local help = read("doc/unreal.txt")

    for _, tag in ipairs({ "*unreal.nvim*", "*unreal-commands*", "*unreal-config*", "*:Unreal*" }) do
        it("has tag " .. tag, function()
            assert.is_truthy(help:find(tag, 1, true))
        end)
    end

    it(":helptags reports no duplicate tags", function()
        local dir = h.tmpdir()
        vim.fn.mkdir(dir .. "/doc", "p")
        vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(h.repo_root, "doc/unreal.txt")), dir .. "/doc/unreal.txt")
        -- nightly :helptags is Lua and calls global assert(); luassert's returns extra values (E118)
        local luassert = _G.assert
        _G.assert = _PlenaryBustedOldAssert or luassert
        local ok = pcall(vim.cmd.helptags, vim.fn.fnameescape(dir .. "/doc"))
        _G.assert = luassert
        assert.is_true(ok)
    end)

    it("README and help agree on the WIP notice", function()
        local readme = read("README.md"):lower()
        local inHelp = help:lower():find("work in progress", 1, true) ~= nil
        local inReadme = readme:find("work in progress", 1, true) ~= nil
        assert.are.equal(inHelp, inReadme)
    end)
end)
