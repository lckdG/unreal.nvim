local h = dofile("tests/helpers.lua")
local config = require("unreal.config")

describe("config", function()
    after_each(h.reset)

    it("nil opts -> defaults", function()
        config.config(nil)
        assert.are.same(config.defaults, config.opts)
    end)

    it("deep-merges nested opts", function()
        config.config({ custom_treesitter = { revision = "x" } })
        assert.are.equal("x", config.opts.custom_treesitter.revision)
        assert.are.equal(config.defaults.custom_treesitter.url, config.opts.custom_treesitter.url)
    end)

    it("GetClangdBuildArgs returns the configured list", function()
        config.config({ clangd_build_args = { "-a", "-b" } })
        local args = config.GetClangdBuildArgs()
        assert.are.same({ "-a", "-b" }, args)
    end)

    it("GetClangdBuildArgs with nil -> {}", function()
        config.config()
        config.opts.clangd_build_args = nil
        assert.are.same({}, config.GetClangdBuildArgs())
    end)
end)

describe("commands", function()
    local subcommands = {
        SetEnginePath = { "unreal.engine", "InputEnginePath" },
        OpenProject = { "unreal.project", "OpenUproject" },
        RebuildClangd = { "unreal.project", "RebuildClangd" },
        SwitchSourceHeader = { "unreal.search", "SwitchSourceHeader" },
        CreateImpl = { "unreal.impl", "ImplementFunction" },
        CompleteMacro = { "unreal.macros", "CompleteMacro" },
        FindSource = { "unreal.search", "FindSource" },
        GrepSource = { "unreal.search", "GrepSource" },
    }

    local function init(opts)
        config.config(opts)
        require("unreal.commands").init(config.opts)
    end

    after_each(function()
        h.reset()
        pcall(vim.api.nvim_del_user_command, "Unreal")
        pcall(vim.api.nvim_del_user_command, "UE")
        vim.cmd("silent! cabclear")
    end)

    it("command_lead = 'UE' creates :UE, not :Unreal", function()
        init({ command_lead = "UE" })
        local cmds = vim.api.nvim_get_commands({})
        assert.is_not_nil(cmds.UE)
        assert.is_nil(cmds.Unreal)
    end)

    it("unknown subcommand -> error notify", function()
        local notes = h.notifications()
        init()
        vim.cmd("Unreal Foo")
        assert.is_true(h.notified(notes, "Error: unavailable command Foo", vim.log.levels.ERROR))
    end)

    it("<Tab> completes all subcommands", function()
        init()
        local got = vim.fn.getcompletion("Unreal ", "cmdline")
        table.sort(got)
        local want = vim.tbl_keys(subcommands)
        table.sort(want)
        assert.are.same(want, got)
    end)

    for name, target in pairs(subcommands) do
        it(name .. " dispatches to " .. target[1] .. "." .. target[2], function()
            local calls = h.spy(require(target[1]), target[2])
            init()
            vim.cmd("Unreal " .. name)
            assert.are.equal(1, #calls)
        end)
    end

    it("cmd_abbreviations expand with command_lead", function()
        init({ command_lead = "UE", cmd_abbreviations = { uo = "OpenProject" } })
        assert.are.equal("UE OpenProject", vim.fn.maparg("uo", "c", true))
    end)

    it("empty cmd_abbreviations -> none", function()
        init({ cmd_abbreviations = {} })
        assert.are.equal("", vim.fn.maparg("uo", "c", true))
    end)
end)

describe("telescope.AppendIgnorePatterns", function()
    local telescope = require("unreal.telescope")

    after_each(function()
        h.reset()
        package.loaded["telescope"] = nil
        package.loaded["telescope.config"] = nil
    end)

    local function fake_telescope(existing)
        local calls = {}
        package.loaded["telescope"] = {}
        package.loaded["telescope.config"] = {
            values = { file_ignore_patterns = existing },
            set_defaults = function(...) table.insert(calls, { ... }) end,
        }
        return calls
    end

    it("appends to the user's patterns", function()
        local calls = fake_telescope({ "user%.txt" })
        telescope.AppendIgnorePatterns({ "%.uasset" })
        assert.are.same({ "user%.txt", "%.uasset" }, calls[1][1].file_ignore_patterns)
    end)

    it("telescope not installed -> no error", function()
        assert.has_no.errors(function() telescope.AppendIgnorePatterns({ "%.uasset" }) end)
    end)

    it("nil ignores -> defaults untouched", function()
        local calls = fake_telescope({ "user%.txt" })
        telescope.AppendIgnorePatterns(nil)
        assert.are.equal(0, #calls)
    end)
end)

describe("treesitter.Hijack", function()
    local treesitter = require("unreal.treesitter")

    local function tsupdate_autocmds()
        return #vim.api.nvim_get_autocmds({ event = "User", pattern = "TSUpdate" })
    end

    after_each(function()
        h.reset()
        vim.api.nvim_clear_autocmds({ event = "User", pattern = "TSUpdate" })
        package.loaded["nvim-treesitter.parsers"] = nil
    end)

    it("nil opts -> no TSUpdate autocmd", function()
        treesitter.Hijack(nil)
        assert.are.equal(0, tsupdate_autocmds())
    end)

    it("TSUpdate overrides the cpp parser", function()
        package.loaded["nvim-treesitter.parsers"] = {}
        treesitter.Hijack({ url = "https://example.com/grammar", revision = "abc" })
        assert.are.equal(1, tsupdate_autocmds())
        vim.api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
        assert.are.same({
            install_info = { url = "https://example.com/grammar", revision = "abc" },
            tier = 2,
        }, package.loaded["nvim-treesitter.parsers"].cpp)
    end)
end)
