local h = dofile("tests/helpers.lua")

local function read(rel)
    return table.concat(vim.fn.readfile(vim.fs.joinpath(h.repo_root, rel)), "\n")
end

local function command_tags()
    local config = require("unreal.config")
    config.config()
    require("unreal.commands").init(config.opts)
    local tags = {}
    for _, group in ipairs(vim.fn.getcompletion("Unreal ", "cmdline")) do
        for _, action in ipairs(vim.fn.getcompletion("Unreal " .. group .. " ", "cmdline")) do
            table.insert(tags, ("*:Unreal-%s-%s*"):format(group, action))
        end
    end
    vim.api.nvim_del_user_command("Unreal")
    return tags
end

describe("help file", function()
    local help = read("doc/unreal.txt")
    local commandTags = command_tags()

    it("finds the :Unreal subcommands to check", function()
        assert.is_true(#commandTags > 0)
    end)

    for _, tag in
        ipairs(vim.list_extend({
            "*unreal.nvim*",
            "*unreal-commands*",
            "*unreal-config*",
            "*unreal-extensions*",
            "*:Unreal*",
        }, commandTags))
    do
        it("has tag " .. tag, function()
            assert.is_truthy(help:find(tag, 1, true))
        end)
    end

    it(":helptags reports no duplicate tags", function()
        local dir = h.tmpdir()
        vim.fn.mkdir(dir .. "/doc", "p")
        vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(h.repo_root, "doc/unreal.txt")), dir .. "/doc/unreal.txt")
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
