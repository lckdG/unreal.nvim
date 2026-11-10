local h = dofile("tests/helpers.lua")
h.fake_platform("Linux")
local config = require("unreal.config")
local engine = require("unreal.engine")
local project = require("unreal.project")
local realFindEngineTools = engine.FindEngineTools

local ERROR = vim.log.levels.ERROR
local UBT = h.UBT

local function fake_tools(overrides)
    local tools = {
        RootDir = "/ue",
        EngineExe = { "editor" },
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
        pcall(vim.api.nvim_del_augroup_by_name, "unreal.nvim.project")
        h.reset()
    end)

    describe("EnsureUproject", function()
        local function ensure()
            local calls = 0
            project.EnsureUproject(function()
                calls = calls + 1
            end)
            return calls
        end

        local TWO = { "A/A.uproject", "B/B.uproject" }

        for _, case in ipairs({
            { name = "0 uprojects -> error, no prompt, callback not run", files = {}, prompts = 0, error = true },
            { name = "1 uproject -> used without prompt", files = { "Game.uproject" }, prompts = 0 },
            { name = "2 uprojects, choose 2 -> second one used", files = TWO, choice = 2, prompts = 1 },
            { name = "2 uprojects, select dismissed -> callback not run", files = TWO, prompts = 1 },
        }) do
            it(case.name, function()
                local tree = {}
                for _, file in ipairs(case.files) do
                    tree[file] = {}
                end
                local root = h.project(tree)
                local selects = h.use_select(case.choice)
                local calls = ensure()
                assert.are.equal(case.prompts, #selects)
                assert.are.equal(case.error == true, h.notified(notes, ERROR))
                local want = case.choice and selects[1].items[case.choice].value
                    or (#case.files == 1 and vim.fs.joinpath(root, case.files[1]))
                    or nil
                assert.are.equal(want and 1 or 0, calls)
                assert.are.equal(want, project.UprojectPath)
            end)
        end

        it("chosen uproject is kept -> second call does not prompt", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = h.use_select(2)
            local first = ensure()
            local chosen = project.UprojectPath
            local second = ensure()
            assert.are.equal(2, first + second)
            assert.are.equal(1, #selects)
            assert.are.equal(chosen, project.UprojectPath)
        end)
    end)

    describe("OpenUproject", function()
        it("1 uproject -> jobstart detached, no prompt", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local jobs = h.spy(vim.fn, "jobstart", 1)
            local selects = h.use_select(1)
            project.OpenUproject()
            assert.are.same({ "editor", root .. "/Game.uproject" }, jobs[1][1])
            assert.are.same({ detach = true }, jobs[1][2])
            assert.are.equal(0, #selects)
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
            real_engine({ UBT })
            h.fake_platform("Linux")
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
            return h.run_job(project.RebuildClangd, code)
        end

        it("no engine tools -> error, UBT not called", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools(false)
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("UnrealBuildTool missing -> error, UBT not called", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools({ UnrealBuildTool = vim.NIL })
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("engine without editor -> UBT still runs", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools({ EngineExe = vim.NIL })
            local state = run(0)
            assert.are.equal(1, #state.calls)
            assert.are.equal("/ue/" .. UBT, state.calls[1].cmd[1])
        end)

        describe("real engine tree", function()
            local root

            before_each(function()
                h.project({ ["Game.uproject"] = {} })
                root = real_engine({ UBT })
            end)

            it("runs the engine's RunUBT script", function()
                local state = run(0)
                assert.are.equal(vim.fs.joinpath(root, UBT), state.calls[1].cmd[1])
            end)

            it("no RunUBT script -> error, UBT not called", function()
                vim.fn.delete(vim.fs.joinpath(root, UBT))
                local state = run(0)
                assert.are.equal(0, #state.calls)
                assert.is_true(h.notified(notes, ERROR))
            end)

            it("copies compile_commands.json from the engine root", function()
                run(0)
                assert.are.equal(vim.fs.joinpath(root, "compile_commands.json"), copies[1][1])
            end)
        end)

        it("2 uprojects, choose 2 -> UBT gets the second project and its Editor target", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = h.use_select(2)
            local state = run(0)
            assert.are.equal(1, #selects)
            local second = selects[1].items[2].value
            local target = vim.fn.fnamemodify(second, ":t:r") .. "Editor"
            local cmd = state.calls[1].cmd
            assert.is_true(vim.tbl_contains(cmd, "-project=" .. second))
            assert.is_true(vim.tbl_contains(cmd, target))
        end)

        it("runs RunUBT via jobstart in a terminal with an argument list", function()
            local root = h.project({ ["Game.uproject"] = {} })
            h.fake_platform("Linux")
            config.opts.clangd_build_args = { "-NoExecCodeGenActions" }
            local state = run(0)
            assert.are.same({
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
            local state = h.stub_jobstart(0)
            project.RebuildClangd()
            local jobWin = state.calls[1].win
            assert.are_not.equal(origWin, jobWin)
            vim.api.nvim_set_current_win(origWin)
            h.wait_job(state)
            assert.is_nil(state.callback_error)
            assert.are.equal(jobWin, vim.api.nvim_get_current_win())
        end)

        it("terminal window closed before exit -> no error", function()
            h.project({ ["Game.uproject"] = {} })
            local state = h.stub_jobstart(0)
            project.RebuildClangd()
            vim.api.nvim_win_close(state.calls[1].win, true)
            h.wait_job(state)
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
            assert.is_true(h.notified(notes, ERROR, "(6)"))
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

    describe("BuildEditor", function()
        before_each(function()
            vim.fn.setqflist({}, "f")
            h.fake_platform("Linux")
        end)

        local function run(code, chunks)
            return h.run_job(project.BuildEditor, code, chunks)
        end

        it("no engine tools -> error, UBT not called", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools(false)
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("UnrealBuildTool missing -> error, UBT not called", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools({ UnrealBuildTool = vim.NIL })
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("engine without editor -> UBT still runs", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools({ EngineExe = vim.NIL })
            local state = run(0)
            assert.are.equal(1, #state.calls)
        end)

        it("runs RunUBT via jobstart in a terminal with an argument list", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local state = run(0)
            assert.are.same({
                "/ue/" .. UBT,
                "GameEditor",
                "Linux",
                "Development",
                "-project=" .. root .. "/Game.uproject",
                "-WaitMutex",
            }, state.calls[1].cmd)
            assert.is_true(state.calls[1].opts.term)
        end)

        it("2 uprojects, choose 2 -> UBT gets the second project and its Editor target", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = h.use_select(2)
            local state = run(0)
            local second = selects[1].items[2].value
            local cmd = state.calls[1].cmd
            assert.is_true(vim.tbl_contains(cmd, "-project=" .. second))
            assert.is_true(vim.tbl_contains(cmd, "BEditor"))
        end)

        it("opens a split for the terminal and focuses it after exit", function()
            h.project({ ["Game.uproject"] = {} })
            local origWin = vim.api.nvim_get_current_win()
            local state = h.stub_jobstart(0)
            project.BuildEditor()
            local jobWin = state.calls[1].win
            assert.are_not.equal(origWin, jobWin)
            vim.api.nvim_set_current_win(origWin)
            h.wait_job(state)
            assert.is_nil(state.callback_error)
            assert.are.equal(jobWin, vim.api.nvim_get_current_win())
        end)

        it("terminal window closed before exit -> no error", function()
            h.project({ ["Game.uproject"] = {} })
            local state = h.stub_jobstart(5)
            project.BuildEditor()
            vim.api.nvim_win_close(state.calls[1].win, true)
            h.wait_job(state)
            assert.is_nil(state.callback_error)
        end)

        it("exit code 0 -> no error, quickfix untouched", function()
            h.project({ ["Game.uproject"] = {} })
            local state = run(0, { { "/src/A.cpp:1:1: error: stale\r", "" } })
            assert.is_nil(state.callback_error)
            assert.is_false(h.notified(notes, ERROR))
            assert.are.equal(0, vim.fn.getqflist({ nr = "$" }).nr)
        end)

        it("exit code != 0 -> error with exit code", function()
            h.project({ ["Game.uproject"] = {} })
            local state = run(6)
            assert.is_nil(state.callback_error)
            assert.is_true(h.notified(notes, ERROR, "(6)"))
        end)

        it("exit code != 0 -> only error lines in quickfix", function()
            h.project({ ["Game.uproject"] = {} })
            run(6, {
                {
                    "Building GameEditor...\r",
                    "/src/A.cpp:10:5: error: boom\r",
                    "/src/B.cpp:3:1: warning: unused\r",
                    "\27[31m/src/C.h:7:2: error: red\27[0m\r",
                    "",
                },
            })
            local items = vim.tbl_map(function(item)
                return { vim.fn.bufname(item.bufnr), item.lnum, item.col, item.type, item.text }
            end, vim.fn.getqflist())
            assert.are.same({
                { "/src/A.cpp", 10, 5, "e", "boom" },
                { "/src/C.h", 7, 2, "e", "red" },
            }, items)
        end)

        it("error line split across stdout chunks -> one quickfix entry", function()
            h.project({ ["Game.uproject"] = {} })
            run(6, { { "/src/A.cpp:10" }, { ":5: error: boom\r", "" } })
            local items = vim.fn.getqflist()
            assert.are.equal(1, #items)
            assert.are.equal("boom", items[1].text)
        end)

        it("last error line without newline -> still in quickfix", function()
            h.project({ ["Game.uproject"] = {} })
            run(6, { { "noise\r", "/src/A.cpp:10:5: error: boom" } })
            assert.are.equal(1, #vim.fn.getqflist())
        end)

        it("Win64 -> MSVC error lines in quickfix", function()
            h.fake_platform("Win64")
            h.project({ ["Game.uproject"] = {} })
            run(6, {
                {
                    "C:\\src\\A.cpp(10,5): error C2065: boom\r",
                    "C:\\src\\B.cpp(3): error C1083: gone\r",
                    "C:\\src\\C.cpp(1,1): warning C4100: unused\r",
                    "",
                },
            })
            local items = vim.fn.getqflist()
            assert.are.equal(2, #items)
            assert.are.same({ 10, 5, "C2065: boom" }, { items[1].lnum, items[1].col, items[1].text })
            assert.are.same({ 3, "C1083: gone" }, { items[2].lnum, items[2].text })
        end)
    end)

    describe("BuildEditorClean", function()
        before_each(function()
            vim.fn.setqflist({}, "f")
            h.fake_platform("Linux")
        end)

        local function run(code, chunks)
            return h.run_job(project.BuildEditorClean, code, chunks)
        end

        it("no engine tools -> error, UBT not called", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools(false)
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("UnrealBuildTool missing -> error, UBT not called", function()
            h.project({ ["Game.uproject"] = {} })
            use_tools({ UnrealBuildTool = vim.NIL })
            local state = run(0)
            assert.are.equal(0, #state.calls)
            assert.is_true(h.notified(notes, ERROR))
        end)

        it("runs RunUBT with -Rebuild via jobstart in a terminal", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local state = run(0)
            assert.are.same({
                "/ue/" .. UBT,
                "GameEditor",
                "Linux",
                "Development",
                "-project=" .. root .. "/Game.uproject",
                "-Rebuild",
                "-WaitMutex",
            }, state.calls[1].cmd)
            assert.is_true(state.calls[1].opts.term)
        end)

        it("does not pass -Clean", function()
            h.project({ ["Game.uproject"] = {} })
            local state = run(0)
            assert.is_false(vim.tbl_contains(state.calls[1].cmd, "-Clean"))
        end)

        it("2 uprojects, choose 2 -> UBT gets the second project and its Editor target", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            local selects = h.use_select(2)
            local state = run(0)
            local second = selects[1].items[2].value
            local cmd = state.calls[1].cmd
            assert.is_true(vim.tbl_contains(cmd, "-project=" .. second))
            assert.is_true(vim.tbl_contains(cmd, "BEditor"))
        end)

        it("exit code 0 -> no error, quickfix untouched", function()
            h.project({ ["Game.uproject"] = {} })
            local state = run(0, { { "/src/A.cpp:1:1: error: stale\r", "" } })
            assert.is_nil(state.callback_error)
            assert.is_false(h.notified(notes, ERROR))
            assert.are.equal(0, vim.fn.getqflist({ nr = "$" }).nr)
        end)

        it("exit code != 0 -> error with exit code, error lines in quickfix", function()
            h.project({ ["Game.uproject"] = {} })
            local state = run(6, {
                {
                    "Cleaning GameEditor...\r",
                    "/src/A.cpp:10:5: error: boom\r",
                    "/src/B.cpp:3:1: warning: unused\r",
                    "",
                },
            })
            assert.is_nil(state.callback_error)
            assert.is_true(h.notified(notes, ERROR, "(6)"))
            local items = vim.fn.getqflist()
            assert.are.equal(1, #items)
            assert.are.equal("boom", items[1].text)
        end)

        it("exit code != 0 without error lines -> quickfix untouched", function()
            h.project({ ["Game.uproject"] = {} })
            run(6, { { "Cleaning GameEditor...\r", "" } })
            assert.are.equal(0, vim.fn.getqflist({ nr = "$" }).nr)
        end)
    end)

    describe("EditUproject", function()
        local function current_file()
            return vim.api.nvim_buf_get_name(0)
        end

        it("1 uproject -> opened in current window, no prompt", function()
            local root = h.project({ ["Game.uproject"] = {} })
            local selects = h.use_select(1)
            project.EditUproject()
            assert.are.equal(0, #selects)
            assert.are.equal(root .. "/Game.uproject", current_file())
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
            local selects = h.use_select(2)
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
            local selects = h.use_select(1)
            project.SelectUproject_User()
            h.use_select(2)
            project.SelectUproject_User()
            assert.are.equal(1, #selects)
            assert.is_true(h.ends_with(project.UprojectPath, "B/B.uproject"))
        end)

        it("select dismissed -> previous choice kept", function()
            h.project({ ["A/A.uproject"] = {}, ["B/B.uproject"] = {} })
            h.use_select(1)
            project.SelectUproject_User()
            local before = project.UprojectPath
            h.use_select(nil)
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

        it("does not search subfolders or notify", function()
            h.project({})
            local finds = h.spy(require("unreal.path_utils"), "FindUprojects", {})
            project.init()
            assert.are.equal(0, #finds)
            assert.are.equal(0, #notes)
        end)

        it("one uproject in the project root -> chosen", function()
            local root = h.project({ ["Game.uproject"] = {} })
            project.init()
            assert.are.equal(root .. "/Game.uproject", project.UprojectPath)
        end)

        it("two uprojects in the project root -> first by name chosen", function()
            local root = h.project({ ["B.uproject"] = {}, ["A.uproject"] = {} })
            project.init()
            assert.are.equal(root .. "/A.uproject", project.UprojectPath)
        end)

        it("uproject only in a subfolder -> none chosen", function()
            h.project({ [".git/HEAD"] = {}, ["Game/Game.uproject"] = {} })
            project.init()
            assert.is_nil(project.UprojectPath)
        end)

        it("folder named like a uproject -> ignored", function()
            h.project({ ["Fake.uproject/x.txt"] = {} })
            project.init()
            assert.is_nil(project.UprojectPath)
        end)

        it(":cd to another project -> its uproject chosen, engine override reset", function()
            h.project({ ["A.uproject"] = {} })
            project.init()
            engine.OverrideEnginePath = "/ue"
            local other = h.project({ ["B.uproject"] = {} })
            assert.are.equal(other, project.ProjectRoot)
            assert.are.equal(other .. "/B.uproject", project.UprojectPath)
            assert.is_nil(engine.OverrideEnginePath)
        end)

        it(":cd to a folder without uproject -> previous choice cleared", function()
            h.project({ ["A.uproject"] = {} })
            project.init()
            h.project({})
            assert.is_nil(project.UprojectPath)
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

    describe("EditBuildConfiguration", function()
        local userFile, confirms
        local ENGINE_CONFIG = "/ue/Engine/Saved/UnrealBuildTool/BuildConfiguration.xml"

        local function current_file()
            return vim.api.nvim_buf_get_name(0)
        end

        local function names(items)
            return vim.tbl_map(function(item)
                return item.name
            end, items)
        end

        local function answer(choice)
            confirms = h.spy(vim.fn, "confirm", choice)
        end

        before_each(function()
            userFile = vim.fs.joinpath(h.tmpdir(), "Unreal Engine", "UnrealBuildTool", "BuildConfiguration.xml")
            h.stub(require("unreal.path_utils"), "GetUserBuildConfig", function()
                return { { name = "User Config", value = userFile } }
            end)
            answer(1)
        end)

        it("no uproject chosen -> only user entries, engine not looked up", function()
            h.project({})
            local finds = use_tools()
            local selects = h.use_select(nil)
            project.EditBuildConfiguration()
            assert.are.same({ "User Config" }, names(selects[1].items))
            assert.are.equal(0, #finds)
        end)

        it("uproject chosen -> project, user and engine entries", function()
            local root = h.project({ [".git/HEAD"] = {}, ["Game/Game.uproject"] = {} })
            project.UprojectPath = root .. "/Game/Game.uproject"
            use_tools({ BuildConfig = ENGINE_CONFIG })
            local selects = h.use_select(nil)
            project.EditBuildConfiguration()
            local items = selects[1].items
            assert.are.same({ "Project Config", "User Config", "Engine Config" }, names(items))
            assert.are.equal(root .. "/Game/Saved/UnrealBuildTool/BuildConfiguration.xml", items[1].value)
            assert.are.equal(ENGINE_CONFIG, items[3].value)
        end)

        it("engine not found -> no engine entry", function()
            local root = h.project({ ["Game.uproject"] = {} })
            project.UprojectPath = root .. "/Game.uproject"
            use_tools(false)
            local selects = h.use_select(nil)
            project.EditBuildConfiguration()
            assert.are.same({ "Project Config", "User Config" }, names(selects[1].items))
        end)

        it("existing file -> opened as is, no confirm", function()
            h.project({})
            h.write(vim.fs.dirname(userFile), "BuildConfiguration.xml", { "<Configuration/>" })
            h.use_select(1)
            project.EditBuildConfiguration()
            assert.are.equal(userFile, current_file())
            assert.are.same({ "<Configuration/>" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
            assert.are.equal(0, #confirms)
        end)

        it("missing file, Yes -> template in buffer, folders created, file written on save", function()
            h.project({})
            h.use_select(1)
            project.EditBuildConfiguration()
            local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            assert.are.equal(userFile, current_file())
            assert.are.equal(1, #confirms)
            assert.are.equal(3, #lines)
            assert.is_truthy(lines[1]:find("<?xml", 1, true))
            assert.are.equal("</Configuration>", lines[3])
            assert.are.equal(1, vim.fn.isdirectory(vim.fs.dirname(userFile)))
            assert.are.equal(0, vim.fn.filereadable(userFile))
        end)

        it("missing file picked again before saving -> same buffer, template not duplicated", function()
            h.project({})
            h.use_select(1)
            project.EditBuildConfiguration()
            local buf = vim.api.nvim_get_current_buf()
            project.EditBuildConfiguration()
            vim.cmd.enew()
            project.EditBuildConfiguration()
            assert.are.equal(buf, vim.api.nvim_get_current_buf())
            assert.are.equal(3, #vim.api.nvim_buf_get_lines(0, 0, -1, false))
        end)

        it("missing file, No -> nothing opened, no folder created", function()
            h.project({})
            answer(2)
            h.use_select(1)
            local before = current_file()
            project.EditBuildConfiguration()
            assert.are.equal(before, current_file())
            assert.are.equal(0, vim.fn.isdirectory(vim.fs.dirname(userFile)))
        end)

        it("list dismissed -> nothing opened, no confirm", function()
            h.project({})
            h.use_select(nil)
            local before = current_file()
            project.EditBuildConfiguration()
            assert.are.equal(before, current_file())
            assert.are.equal(0, #confirms)
        end)
    end)
end)
