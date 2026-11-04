local h = dofile("tests/helpers.lua")
local config = require("unreal.config")
local engine = require("unreal.engine")
local project = require("unreal.project")
local system = require("unreal.system")
local realGetExecuteCmd = engine.GetExecuteCmd
local realGetUbtDll = engine.GetUbtDll
local realGetDotNetCmd = engine.GetDotNetCmd

local ERROR = vim.log.levels.ERROR

local function stub_jobstart(code)
    local state = { calls = {}, exited = false }
    h.stub(vim.fn, "jobstart", function(cmd, opts)
        table.insert(state.calls, { cmd = cmd, opts = opts, win = vim.api.nvim_get_current_win() })
        -- real jobstart fires on_exit later on the main loop
        vim.schedule(function()
            local ok, err = pcall(opts.on_exit, 1, code, "exit")
            state.callback_error = not ok and tostring(err) or nil
            state.exited = true
        end)
        return 1
    end)
    return state
end

describe("project", function()
    local notes

    before_each(function()
        config.config()
        notes = h.notifications()
        h.stub(engine, "EnsureEnginePath", function()
            return true
        end)
        h.stub(engine, "EnginePath", "/ue")
        h.stub(engine, "GetUbtDll", function()
            return "/ue/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"
        end)
        h.stub(engine, "GetDotNetCmd", function()
            return "/ue/dotnet"
        end)
        h.stub(engine, "GetExecuteCmd", function()
            return true, { "editor" }
        end)
    end)
    after_each(h.reset)

    describe("OpenUproject", function()
        it("0 uprojects -> error, no prompt, no jobstart", function()
            h.project({})
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local prompts = h.spy(vim.fn, "inputlist", 1)
            project.OpenUproject()
            assert.is_true(h.notified(notes, ERROR))
            assert.are.equal(0, #jobs)
            assert.are.equal(0, #prompts)
        end)

        it("1 uproject -> jobstart detached, no prompt", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local prompts = h.spy(vim.fn, "inputlist", 1)
            project.OpenUproject()
            assert.are.same({ "editor", root .. "/Game.uproject" }, jobs[1][1])
            assert.are.same({ detach = true }, jobs[1][2])
            assert.are.equal(0, #prompts)
        end)

        it("2 uprojects, choose 2 -> second one opened", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local prompts = h.spy(vim.fn, "inputlist", 2)
            project.OpenUproject()
            assert.are.equal(1, #prompts)
            local second = prompts[1][1][3]:gsub("^2: ", "")
            assert.are.equal(second, jobs[1][1][2])
        end)

        it("2 uprojects, cancel -> nothing opened", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            h.stub(vim.fn, "inputlist", function()
                return 0
            end)
            project.OpenUproject()
            assert.are.equal(0, #jobs)
        end)

        it("EnsureEnginePath false -> returns before searching", function()
            h.project({ ["Game.uproject"] = {} })
            h.stub(engine, "EnsureEnginePath", function()
                return false
            end)
            local finds = h.spy(require("unreal.path_utils"), "FindUprojects", {})
            local jobs = h.spy(vim.fn, "jobstart", 1)
            project.OpenUproject()
            assert.are.equal(0, #finds)
            assert.are.equal(0, #jobs)
        end)

        it("missing editor binary on Linux -> error, no jobstart", function()
            h.project({ ["Game.uproject"] = {} })
            h.stub(engine, "GetExecuteCmd", realGetExecuteCmd)
            h.stub(engine, "EnginePath", h.tmpdir())
            h.stub(system, "GetPlatform", function()
                return "Linux"
            end)
            local jobs = h.spy(vim.fn, "jobstart", 1)
            project.OpenUproject()
            assert.are.equal(0, #jobs)
            assert.is_true(#notes > 0 and notes[#notes].level == ERROR)
        end)
    end)

    describe("RebuildClangd", function()
        local copies

        before_each(function()
            copies = h.spy(vim.uv, "fs_copyfile", true)
        end)

        local function run(code)
            local state = stub_jobstart(code)
            project.RebuildClangd()
            vim.wait(1000, function()
                return state.exited
            end)
            return state
        end

        it("EnsureEnginePath false -> aborts", function()
            h.project({ ["Game.uproject"] = {} })
            h.stub(engine, "EnsureEnginePath", function()
                return false
            end)
            local state = run(0)
            assert.are.equal(0, #state.calls)
        end)

        for _, getter in ipairs({ "GetUbtDll", "GetDotNetCmd" }) do
            it(getter .. " nil -> warn, UBT not called", function()
                h.project({ ["Game.uproject"] = {} })
                h.stub(engine, getter, function()
                    return nil
                end)
                local state = run(0)
                assert.are.equal(0, #state.calls)
                assert.is_true(h.notified(notes, vim.log.levels.WARN))
            end)
        end

        it("0 uprojects -> error, UBT not called", function()
            h.project({})
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        describe("dotnet resolved from a real engine tree", function()
            local root, bundled

            before_each(function()
                h.project({ ["Game.uproject"] = {} })
                h.stub(engine, "GetUbtDll", realGetUbtDll)
                h.stub(engine, "GetDotNetCmd", realGetDotNetCmd)
                root = h.tmpdir()
                h.write(root, "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll")
                local plat = ({ Win64 = "win", Linux = "linux", Mac = "mac" })[system.GetPlatform()]
                local exe = system.GetPlatform() == "Win64" and "dotnet.exe" or "dotnet"
                bundled = h.write(
                    root,
                    vim.fs.joinpath("Engine/Binaries/ThirdParty/DotNet/8.0.300", plat .. "-" .. system.GetArch(), exe)
                )
                h.stub(engine, "EnginePath", root)
                h.stub(engine, "EnginePathSet", true)
            end)

            local function path_dotnet(path)
                h.stub(vim.fn, "exepath", function()
                    return path
                end)
            end

            it("bundled dotnet wins over PATH", function()
                path_dotnet("/usr/bin/dotnet")
                local state = run(0)
                assert.are.equal(bundled, state.calls[1].cmd[1])
            end)

            it("no bundled dotnet -> falls back to PATH", function()
                path_dotnet("/usr/bin/dotnet")
                vim.fn.delete(bundled)
                local state = run(0)
                assert.are.equal("/usr/bin/dotnet", state.calls[1].cmd[1])
            end)

            it("neither -> warn, UBT not called", function()
                path_dotnet("")
                vim.fn.delete(bundled)
                local state = run(0)
                assert.are.equal(0, #state.calls)
                assert.is_true(h.notified(notes, vim.log.levels.WARN))
            end)
        end)

        it("2 uprojects, cancel -> UBT not called", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            h.stub(vim.fn, "inputlist", function()
                return 0
            end)
            local state = run(0)
            assert.are.equal(0, #state.calls)
        end)

        it("2 uprojects, choose 2 -> UBT gets the second project and its Editor target", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local prompts = h.spy(vim.fn, "inputlist", 2)
            local state = run(0)
            assert.are.equal(1, #prompts)
            local second = prompts[1][1][3]:gsub("^2: ", "")
            local target = vim.fn.fnamemodify(second, ":t:r") .. "Editor"
            local cmd = state.calls[1].cmd
            assert.is_true(vim.tbl_contains(cmd, "-project=" .. second))
            assert.is_true(vim.tbl_contains(cmd, target))
        end)

        it("runs dotnet via jobstart in a terminal with an argument list", function()
            local root = h.project({ ["Game.uproject"] = {} })
            h.stub(system, "GetPlatform", function()
                return "Linux"
            end)
            config.opts.clangd_build_args = { "-NoExecCodeGenActions" }
            local state = run(0)
            assert.are.same({
                engine.GetDotNetCmd(),
                engine.GetUbtDll(),
                "-mode=GenerateClangDatabase",
                "-NoExecCodeGenActions",
                "-project=" .. root .. "/Game.uproject",
                "-game",
                "-engine",
                "GameEditor",
                "Linux",
                "Development",
            }, state.calls[1].cmd)
            assert.is_true(state.calls[1].opts.term)
        end)

        it("opens a split for the terminal and focuses it after exit", function()
            h.project({ ["Game.uproject"] = {} })
            local origWin = vim.api.nvim_get_current_win()
            local state = stub_jobstart(0)
            project.RebuildClangd()
            local jobWin = state.calls[1].win
            assert.are_not.equal(origWin, jobWin)
            vim.api.nvim_set_current_win(origWin) -- user moves away during build
            vim.wait(1000, function()
                return state.exited
            end)
            assert.is_nil(state.callback_error)
            assert.are.equal(jobWin, vim.api.nvim_get_current_win())
        end)

        it("terminal window closed before exit -> no error", function()
            h.project({ ["Game.uproject"] = {} })
            local state = stub_jobstart(0)
            project.RebuildClangd()
            vim.api.nvim_win_close(state.calls[1].win, true)
            vim.wait(1000, function()
                return state.exited
            end)
            assert.is_nil(state.callback_error)
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
        end)

        it("engine path with spaces stays one argument", function()
            h.project({ ["Game.uproject"] = {} })
            local dll = "C:/Program Files/Epic Games/UE_5.4/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"
            h.stub(engine, "GetUbtDll", function()
                return dll
            end)
            local state = run(0)
            assert.is_true(vim.tbl_contains(state.calls[1].cmd, dll))
        end)

        it("each clangd_build_args entry is a separate argument", function()
            h.project({ ["Game.uproject"] = {} })
            config.opts.clangd_build_args = { "-a", "-b" }
            local state = run(0)
            local cmd = state.calls[1].cmd
            assert.is_true(vim.tbl_contains(cmd, "-a"))
            assert.is_true(vim.tbl_contains(cmd, "-b"))
        end)

        it("exit code != 0 -> no copy, error with exit code", function()
            h.project({ ["Game.uproject"] = {} })
            local state = run(6)
            assert.is_nil(state.callback_error)
            assert.are.equal(0, #copies)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("exit code 0 -> copies compile_commands.json to cwd, success notify", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local state = run(0)
            assert.is_nil(state.callback_error)
            assert.are.same({ "/ue/compile_commands.json", root .. "/compile_commands.json" }, copies[1])
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
        end)

        it("copy fails -> error with reason", function()
            h.project({ ["Game.uproject"] = {} })
            h.stub(vim.uv, "fs_copyfile", function()
                return nil, "ENOENT: no such file"
            end)
            local state = run(0)
            assert.is_nil(state.callback_error)
            assert.is_true(h.notified(notes, ERROR, "ENOENT: no such file"))
        end)
    end)
end)
