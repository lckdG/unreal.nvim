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

    describe("IsExtensionEnabled", function()
        for _, case in ipairs({ { true, true }, { {}, true }, { false, false } }) do
            it(vim.inspect(case[1]) .. " -> " .. tostring(case[2]), function()
                config.config({ extensions = { telescope = case[1] } })
                assert.are.equal(case[2], config.IsExtensionEnabled("telescope"))
            end)
        end

        it("not listed -> false", function()
            config.config()
            assert.is_false(config.IsExtensionEnabled("telescope"))
        end)

        it("before config() -> false, no error", function()
            h.stub(config, "opts", nil)
            assert.is_false(config.IsExtensionEnabled("telescope"))
        end)
    end)

    describe("deprecated telescope_extended_ignores", function()
        local deprecations

        before_each(function()
            deprecations = h.spy(vim, "deprecate")
        end)

        it("warns and moves ignores into extensions.telescope", function()
            config.config({ telescope_extended_ignores = { "%.exe" } })
            assert.are.equal(1, #deprecations)
            assert.are.equal("telescope_extended_ignores", deprecations[1][1])
            assert.are.same({ ignores = { "%.exe" } }, config.opts.extensions.telescope)
        end)

        it("telescope = true -> replaced by table with ignores", function()
            config.config({ telescope_extended_ignores = { "%.exe" }, extensions = { telescope = true } })
            assert.are.same({ ignores = { "%.exe" } }, config.opts.extensions.telescope)
        end)

        it("new ignores win over the old option", function()
            config.config({
                telescope_extended_ignores = { "%.exe" },
                extensions = { telescope = { ignores = { "%.dll" } } },
            })
            assert.are.same({ "%.dll" }, config.opts.extensions.telescope.ignores)
        end)

        it("telescope = false -> stays disabled", function()
            config.config({ telescope_extended_ignores = { "%.exe" }, extensions = { telescope = false } })
            assert.is_false(config.opts.extensions.telescope)
        end)

        it("old option unset -> no warning", function()
            config.config()
            assert.are.equal(0, #deprecations)
        end)
    end)
end)

describe("commands", function()
    local subcommands = {
        ["Engine SetPath"] = { "unreal.engine", "InputEnginePath" },
        ["Project Open"] = { "unreal.project", "OpenUproject" },
        ["Build Clangd"] = { "unreal.project", "RebuildClangd" },
        ["Code Impl"] = { "unreal.impl", "ImplementFunction" },
        ["Code Macro"] = { "unreal.macros", "CompleteMacro" },
        ["Code SwitchSourceHeader"] = { "unreal.search", "SwitchSourceHeader" },
        ["Search Files"] = { "unreal.search", "FindSource" },
        ["Search Grep"] = { "unreal.search", "GrepSource" },
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

    for name, target in pairs(subcommands) do
        it(name .. " dispatches to " .. target[1] .. "." .. target[2], function()
            local calls = h.spy(require(target[1]), target[2])
            init()
            vim.cmd("Unreal " .. name)
            assert.are.equal(1, #calls)
        end)
    end

    it("extra spaces between group and action -> still dispatches", function()
        local calls = h.spy(require("unreal.project"), "RebuildClangd")
        init()
        vim.cmd("Unreal   Build   Clangd  ")
        assert.are.equal(1, #calls)
    end)

    for _, case in ipairs({
        { "Unreal ", { "Build", "Code", "Engine", "Project", "Search" } },
        { "Unreal Bu", { "Build" } },
        { "Unreal Code ", { "Impl", "Macro", "SwitchSourceHeader" } },
        { "Unreal Code M", { "Macro" } },
        { "Unreal Search ", { "Files", "Grep" } },
        { "Unreal Foo ", {} },
        { "Unreal Code Impl ", {} },
    }) do
        it("<Tab> on '" .. case[1] .. "' -> " .. vim.inspect(case[2]), function()
            init()
            assert.are.same(case[2], vim.fn.getcompletion(case[1], "cmdline"))
        end)
    end

    it("cmd_abbreviations expand with command_lead", function()
        init({ command_lead = "UE", cmd_abbreviations = { uo = "Project Open" } })
        assert.are.equal("UE Project Open", vim.fn.maparg("uo", "c", true))
    end)

    it("empty cmd_abbreviations -> none", function()
        init({ cmd_abbreviations = {} })
        assert.are.equal("", vim.fn.maparg("uo", "c", true))
    end)
end)

describe("setup() extensions", function()
    local ui = require("unreal.ui")

    before_each(function()
        h.stub(require("unreal.engine"), "init", function() end)
        h.stub(require("unreal.project"), "init", function() end)
        h.stub(ui, "provider", ui.provider)
    end)

    after_each(function()
        h.reset()
        pcall(vim.api.nvim_del_user_command, "Unreal")
        pcall(vim.api.nvim_del_augroup_by_name, "unreal.nvim.treesitter")
        package.loaded["telescope"] = nil
        package.loaded["telescope.config"] = nil
    end)

    it("telescope = true -> extension set up with {}", function()
        local got = h.spy(require("unreal.extensions.telescope"), "setup")
        require("unreal").setup({ extensions = { telescope = true } })
        assert.are.same({ { {} } }, got)
    end)

    it("telescope = false -> extension not set up", function()
        local got = h.spy(require("unreal.extensions.telescope"), "setup")
        require("unreal").setup({ extensions = { telescope = false } })
        assert.are.equal(0, #got)
    end)

    it("setup() twice -> telescope ignores applied once, still the provider", function()
        local calls = {}
        local values = { file_ignore_patterns = {} }
        package.loaded["telescope"] = {}
        package.loaded["telescope.config"] = {
            values = values,
            set_defaults = function(defaults)
                table.insert(calls, defaults)
                values.file_ignore_patterns = defaults.file_ignore_patterns
            end,
        }
        local opts = { extensions = { telescope = { ignores = { "%.uasset" } } } }
        require("unreal").setup(opts)
        require("unreal").setup(opts)
        assert.are.equal(1, #calls)
        assert.are.same({ "%.uasset" }, values.file_ignore_patterns)
        assert.are.equal(require("unreal.extensions.telescope"), ui.provider)
    end)

    it("unknown extension -> error notify", function()
        local notes = h.notifications()
        require("unreal").setup({ extensions = { nope = true } })
        assert.is_true(h.notified(notes, vim.log.levels.ERROR))
    end)
end)

describe("treesitter.Hijack", function()
    local treesitter = require("unreal.treesitter")

    local function tsupdate_autocmds()
        return #vim.api.nvim_get_autocmds({ event = "User", pattern = "TSUpdate" })
    end

    after_each(function()
        h.reset()
        pcall(vim.api.nvim_del_augroup_by_name, "unreal.nvim.treesitter")
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

    it("called twice -> one TSUpdate autocmd", function()
        local opts = { url = "https://example.com/grammar", revision = "abc" }
        treesitter.Hijack(opts)
        treesitter.Hijack(opts)
        assert.are.equal(1, tsupdate_autocmds())
    end)

    it("setup() twice -> one TSUpdate autocmd", function()
        -- engine/project init touch the lock file and prompt; not under test here
        h.stub(require("unreal.engine"), "init", function() end)
        h.stub(require("unreal.project"), "init", function() end)
        local unreal = require("unreal")
        unreal.setup()
        unreal.setup()
        pcall(vim.api.nvim_del_user_command, "Unreal")
        assert.are.equal(1, tsupdate_autocmds())
    end)
end)
