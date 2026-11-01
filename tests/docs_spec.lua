local h = dofile("tests/helpers.lua")

local function read(rel)
    return table.concat(vim.fn.readfile(vim.fs.joinpath(h.repo_root, rel)), "\n")
end

describe("README", function()
    local readme = read("README.md")

    it("requires nvim-treesitter main and :TSUpdate cpp", function()
        assert.is_truthy(readme:find("nvim-treesitter", 1, true))
        assert.is_truthy(readme:find("main", 1, true))
        assert.is_truthy(readme:find("TSUpdate cpp", 1, true))
    end)

    it("warns the cpp override is global and has no opt-out", function()
        assert.is_truthy(readme:find("every C++ file", 1, true))
        assert.is_truthy(readme:find("no opt-out", 1, true))
        assert.is_nil(readme:find("Set to nil", 1, true))
    end)

    it("lists nvim-lspconfig and documents command_lead", function()
        assert.is_truthy(readme:find("nvim-lspconfig", 1, true))
        assert.is_truthy(readme:find("command_lead", 1, true))
    end)
end)

describe("help file", function()
    local help = read("doc/unreal.txt")

    for _, tag in ipairs({ "*unreal.nvim*", "*unreal-commands*", "*unreal-config*", "*:Unreal*" }) do
        it("has tag " .. tag, function()
            assert.is_truthy(help:find(tag, 1, true))
        end)
    end

    it("has no generic M.* tags", function()
        assert.is_nil(help:find("*M.", 1, true))
    end)

    it(":helptags reports no duplicate tags", function()
        local dir = h.tmpdir()
        vim.fn.mkdir(dir .. "/doc", "p")
        vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(h.repo_root, "doc/unreal.txt")), dir .. "/doc/unreal.txt")
        assert.has_no.errors(function() vim.cmd.helptags(vim.fn.fnameescape(dir .. "/doc")) end)
    end)

    it("README and help agree on the WIP notice", function()
        local readme = read("README.md"):lower()
        local inHelp = help:lower():find("work in progress", 1, true) ~= nil
        local inReadme = readme:find("work in progress", 1, true) ~= nil
        assert.are.equal(inHelp, inReadme)
    end)
end)
