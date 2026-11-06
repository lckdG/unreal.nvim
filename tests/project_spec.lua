local h = dofile("tests/helpers.lua")
local config = require("unreal.config")
local engine = require("unreal.engine")
local project = require("unreal.project")
local system = require("unreal.system")
local ui = require("unreal.ui")
local realFindEngineTools = engine.FindEngineTools

local ERROR = vim.log.levels.ERROR
local UBT = "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"

local function use_select(index)
    local calls = {}
    ui.Use({
        Select = function(items, opts, cb)
            table.insert(calls, { items = items, opts = opts })
            cb(index and items[index] or nil)
        end,
    })
    return calls
end

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

local function fake_tools(overrides)
    local tools = {
        RootDir = "/ue",
        EngineExe = { "editor" },
        DotNetExe = "/ue/dotnet",
        UnrealBuildTool = "/ue/" .. UBT,
    }
    for k, v in pairs(overrides or {}) do
        tools[k] = v ~= vim.NIL and v or nil
    end
    return tools
end

local function use_tools(overrides)
    return h.spy(engine, "FindEngineTools", function(_, cb)
        if overrides == false then
            cb(nil)
        else
            cb(fake_tools(overrides))
        end
    end)
end

local function real_engine(files)
    h.stub(engine, "FindEngineTools", realFindEngineTools)
    local root = h.tmpdir()
    for _, f in ipairs(files) do
        h.write(root, f)
    end
    h.stub(engine, "OverrideEnginePath", root)
    return root
end

describe("project", function()
    local notes

    before_each(function()
        config.config()
        notes = h.notifications()
        h.stub(project, "UprojectPath", nil)
        h.stub(project, "ProjectRoot", nil)
        h.stub(engine, "OverrideEnginePath", nil)
        use_tools()
    end)
    after_each(function()
        ui.Use(nil)
        pcall(vim.api.nvim_del_augroup_by_name, "unreal.nvim.project")
        h.reset()
    end)

    describe("OpenUproject", function()
        it("0 uprojects -> error, no prompt, no jobstart", function()
            h.project({})
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local selects = use_select(1)
            project.OpenUproject()
            assert.is_true(h.notified(notes, ERROR))
            assert.are.equal(0, #jobs)
            assert.are.equal(0, #selects)
        end)

        it("1 uproject -> jobstart detached, no prompt", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local selects = use_select(1)
            project.OpenUproject()
            assert.are.same({ "editor", root .. "/Game.uproject" }, jobs[1][1])
            assert.are.same({ detach = true }, jobs[1][2])
            assert.are.equal(0, #selects)
        end)

        it("2 uprojects, choose 2 -> second one opened", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local selects = use_select(2)
            project.OpenUproject()
            assert.are.equal(1, #selects)
            assert.are.equal(2, #selects[1].items)
            assert.are.equal(selects[1].items[2].value, jobs[1][1][2])
        end)

        it("2 uprojects, select dismissed -> nothing opened", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local selects = use_select(nil)
            project.OpenUproject()
            assert.are.equal(1, #selects)
            assert.are.equal(0, #jobs)
        end)

        it("chosen uproject is kept -> second run does not prompt", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local selects = use_select(2)
            project.OpenUproject()
            project.OpenUproject()
            assert.are.equal(1, #selects)
            assert.are.equal(2, #jobs)
            assert.are.equal(jobs[1][1][2], jobs[2][1][2])
        end)

        it("passes the chosen uproject to FindEngineTools", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local finds = use_tools()
            h.spy(vim.fn, "jobstart", 1)
            project.OpenUproject()
            assert.are.equal(root .. "/Game.uproject", finds[1][1])
        end)

        it("no engine tools -> error, no jobstart", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools(false)
            local jobs = h.spy(vim.fn, "jobstart", 1)
            project.OpenUproject()
            assert.are.equal(0, #jobs)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("engine without editor -> error, no jobstart", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools({ EngineExe = vim.NIL })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            project.OpenUproject()
            assert.are.equal(0, #jobs)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("real engine tree missing editor binary on Linux -> error, no jobstart", function()
            h.project({ ["Game.uproject"] = {} })
            h.stub(vim.fn, "exepath", function()
                return "/usr/bin/dotnet"
            end)
            real_engine({ UBT })
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

        it("no engine tools -> error, UBT not called", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools(false)
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        for _, field in ipairs({ "DotNetExe", "UnrealBuildTool" }) do
            it(field .. " missing -> error, UBT not called", function()
                h.project({ ["Game.uproject"] = {} })
                use_tools({ [field] = vim.NIL })
                local state = run(0)
                assert.are.equal(0, #state.calls)
                assert.is_true(h.notified(notes, ERROR))
            end)
        end

        it("engine without editor -> UBT still runs", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools({ EngineExe = vim.NIL })
            local state = run(0)
            assert.are.equal(1, #state.calls)
            assert.are.equal("/ue/dotnet", state.calls[1].cmd[1])
        end)

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
                local plat = ({ Win64 = "win", Linux = "linux", Mac = "mac" })[system.GetPlatform()]
                local exe = system.GetPlatform() == "Win64" and "dotnet.exe" or "dotnet"
                bundled =
                    vim.fs.joinpath("Engine/Binaries/ThirdParty/DotNet/8.0.300", plat .. "-" .. system.GetArch(), exe)
                root = real_engine({ UBT, bundled })
                bundled = vim.fs.joinpath(root, bundled)
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

            it("neither -> error, UBT not called", function()
                path_dotnet("")
                vim.fn.delete(bundled)
                local state = run(0)
                assert.are.equal(0, #state.calls)
                assert.is_true(h.notified(notes, ERROR))
            end)

            it("copies compile_commands.json from the engine root", function()
                path_dotnet("")
                run(0)
                assert.are.equal(vim.fs.joinpath(root, "compile_commands.json"), copies[1][1])
            end)
        end)

        it("2 uprojects, select dismissed -> UBT not called", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = use_select(nil)
            local state = run(0)
            assert.are.equal(1, #selects)
            assert.are.equal(0, #state.calls)
        end)

        it("2 uprojects, choose 2 -> UBT gets the second project and its Editor target", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = use_select(2)
            local state = run(0)
            assert.are.equal(1, #selects)
            local second = selects[1].items[2].value
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
                "/ue/dotnet",
                "/ue/" .. UBT,
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
            local dll = "C:/Program Files/Epic Games/UE_5.4/" .. UBT
            use_tools({ UnrealBuildTool = dll })
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

        it("exit code 0 -> copies compile_commands.json next to the uproject, success notify", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local state = run(0)
            assert.is_nil(state.callback_error)
            assert.are.same({ "/ue/compile_commands.json", root .. "/compile_commands.json" }, copies[1])
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
        end)

        it("uproject in a subdir of cwd -> copies compile_commands.json next to it", function()
            local root = h.project({ [".git/HEAD"] = {}, ["Game/Game.uproject"] = {} })
            local state = run(0)
            assert.is_nil(state.callback_error)
            assert.are.same({ "/ue/compile_commands.json", root .. "/Game/compile_commands.json" }, copies[1])
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

    describe("EditUproject", function()
        local function current_file()
            return vim.api.nvim_buf_get_name(0)
        end

        it("0 uprojects -> error, current buffer unchanged", function()
            h.project({})
            local before = current_file()
            local selects = use_select(1)
            project.EditUproject()
            assert.is_true(h.notified(notes, ERROR))
            assert.are.equal(0, #selects)
            assert.are.equal(before, current_file())
        end)

        it("1 uproject -> opened in current window, no prompt", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local selects = use_select(1)
            project.EditUproject()
            assert.are.equal(0, #selects)
            assert.are.equal(root .. "/Game.uproject", current_file())
        end)

        it("2 uprojects, choose 2 -> second one opened", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = use_select(2)
            project.EditUproject()
            assert.are.equal(1, #selects)
            assert.are.equal(selects[1].items[2].value, current_file())
        end)

        it("2 uprojects, select dismissed -> current buffer unchanged", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local before = current_file()
            local selects = use_select(nil)
            project.EditUproject()
            assert.are.equal(1, #selects)
            assert.are.equal(before, current_file())
        end)

        it("path with spaces and % -> opened literally", function()
            local root = h.project({ ["My Game%/My Game.uproject"] = {} })
            project.EditUproject()
            assert.are.equal(root .. "/My Game%/My Game.uproject", current_file())
        end)

        it("already open -> switches to it, no duplicate buffer", function()
            local root = h.project({ ["Game.uproject"] = {} })
            project.EditUproject()
            local buf = vim.api.nvim_get_current_buf()
            vim.cmd.enew()
            local listed = #vim.fn.getbufinfo({ buflisted = 1 })
            project.EditUproject()
            assert.are.equal(buf, vim.api.nvim_get_current_buf())
            assert.are.equal(root .. "/Game.uproject", current_file())
            assert.are.equal(listed, #vim.fn.getbufinfo({ buflisted = 1 }))
        end)

        it("cwd below the project -> uproject above is opened", function()
            local root = h.project({ ["Game.uproject"] = {}, ["Source/Game/x.h"] = {} })
            vim.cmd.cd("Source/Game")
            project.init()
            project.EditUproject()
            assert.are.equal(root .. "/Game.uproject", current_file())
        end)

        it("does not look up the engine", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local finds = use_tools()
            project.EditUproject()
            assert.are.equal(root .. "/Game.uproject", current_file())
            assert.are.equal(0, #finds)
        end)
    end)

    describe("SelectUproject_User", function()
        it("2 uprojects, choose 2 -> used by later commands without prompt", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = use_select(2)
            project.SelectUproject_User()
            local chosen = selects[1].items[2].value
            assert.are.equal(chosen, project.UprojectPath)
            local jobs = h.spy(vim.fn, "jobstart", 1)
            project.OpenUproject()
            assert.are.equal(1, #selects)
            assert.are.equal(chosen, jobs[1][1][2])
        end)

        it("asks again even when one is already chosen", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = use_select(1)
            project.SelectUproject_User()
            use_select(2)
            project.SelectUproject_User()
            assert.are.equal(1, #selects)
            assert.is_true(h.ends_with(project.UprojectPath, "B/B.uproject"))
        end)

        it("select dismissed -> previous choice kept", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            use_select(1)
            project.SelectUproject_User()
            local before = project.UprojectPath
            use_select(nil)
            project.SelectUproject_User()
            assert.are.equal(before, project.UprojectPath)
        end)

        it("0 uprojects -> error, nothing chosen", function()
            h.project({})
            project.SelectUproject_User()
            assert.is_nil(project.UprojectPath)
            assert.is_true(h.notified(notes, ERROR))
        end)
    end)

    describe("init", function()
        it("project root is the folder with the uproject when started in a subfolder", function()
            local root = h.project({ ["Game.uproject"] = {}, ["Source/Game/x.h"] = {} })
            vim.cmd.cd("Source/Game")
            project.init()
            assert.are.equal(root, project.ProjectRoot)
        end)

        it("does not search or notify", function()
            h.project({})
            local finds = h.spy(require("unreal.path_utils"), "FindUprojects", {})
            project.init()
            assert.are.equal(0, #finds)
            assert.are.equal(0, #notes)
        end)

        it(":cd to another project -> uproject and engine override reset", function()
            h.project({ ["A.uproject"] = {} })
            project.init()
            project.UprojectPath = "/a/A.uproject"
            engine.OverrideEnginePath = "/ue"
            local other = h.project({ ["B.uproject"] = {} })
            assert.are.equal(other, project.ProjectRoot)
            assert.is_nil(project.UprojectPath)
            assert.is_nil(engine.OverrideEnginePath)
        end)

        it(":cd within the same project -> uproject and engine override kept", function()
            local root = h.project({ ["A.uproject"] = {}, ["Source/Mod/x.h"] = {} })
            project.init()
            project.UprojectPath = root .. "/A.uproject"
            engine.OverrideEnginePath = "/ue"
            vim.cmd.cd("Source/Mod")
            assert.are.equal(root .. "/A.uproject", project.UprojectPath)
            assert.are.equal("/ue", engine.OverrideEnginePath)
        end)

        it("init twice -> one DirChanged autocmd", function()
            h.project({})
            project.init()
            project.init()
            assert.are.equal(1, #vim.api.nvim_get_autocmds({ group = "unreal.nvim.project" }))
        end)
    end)
end)
