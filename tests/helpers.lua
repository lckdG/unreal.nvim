local M = {}

M.repo_root = vim.fn.getcwd()
M.UBT = "Engine/Build/BatchFiles/RunUBT" .. (vim.fn.has("win32") == 1 and ".bat" or ".sh")
M.VERSION_FILE = "Engine/Build/Build.version"

local stubs = {}

function M.stub(tbl, key, value)
    table.insert(stubs, { tbl = tbl, key = key, value = rawget(tbl, key) })
    rawset(tbl, key, value)
    return value
end

function M.spy(tbl, key, ret)
    local calls = {}
    M.stub(tbl, key, function(...)
        table.insert(calls, { ... })
        if type(ret) == "function" then
            return ret(...)
        end
        return ret
    end)
    return calls
end

function M.notifications()
    local list = {}
    M.stub(vim, "notify", function(msg, level)
        table.insert(list, { msg = msg, level = level })
    end)
    return list
end

function M.notified(list, level, stubText)
    for _, n in ipairs(list) do
        if n.level == level and (stubText == nil or n.msg:find(stubText, 1, true)) then
            return true
        end
    end
    return false
end

function M.reset()
    for i = #stubs, 1, -1 do
        local s = stubs[i]
        rawset(s.tbl, s.key, s.value)
    end
    stubs = {}
    local ui = package.loaded["unreal.ui"]
    if ui then
        ui.Use(nil)
    end
    vim.cmd("silent! %bwipeout!")
    vim.cmd.cd(vim.fn.fnameescape(M.repo_root))
end

function M.unload()
    for name in pairs(package.loaded) do
        if name:match("^unreal") then
            package.loaded[name] = nil
        end
    end
end

function M.tmpdir()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    return vim.uv.fs_realpath(dir)
end

function M.write(root, rel, lines)
    local path = vim.fs.joinpath(root, rel)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines or {}, path)
    return path
end

function M.project(files)
    local root = M.tmpdir()
    for rel, lines in pairs(files) do
        M.write(root, rel, lines)
    end
    vim.cmd.cd(vim.fn.fnameescape(root))
    return root
end

function M.edit(rel, row)
    vim.cmd.edit(vim.fn.fnameescape(rel))
    vim.bo.filetype = "cpp"
    vim.treesitter.get_parser(0, "cpp"):parse()
    if row then
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
        vim.api.nvim_win_set_cursor(0, { row, #(line:match("^%s*")) })
    end
end

function M.write_version(root)
    return M.write(root, M.VERSION_FILE, {
        vim.json.encode({ MajorVersion = 5, MinorVersion = 4, PatchVersion = 2 }),
    })
end

function M.write_uproject(root, association)
    local data = association and { EngineAssociation = association } or {}
    return M.write(root, "Game.uproject", { vim.json.encode(data) })
end

function M.answer_input(value)
    return M.spy(vim.ui, "input", function(_, cb)
        cb(value)
    end)
end

function M.use_select(index)
    local calls = {}
    require("unreal.ui").Use({
        Select = function(items, opts, cb)
            table.insert(calls, { items = items, opts = opts })
            cb(index and items[index] or nil)
        end,
    })
    return calls
end

function M.stub_jobstart(code)
    local state = { calls = {}, exited = false }
    M.stub(vim.fn, "jobstart", function(cmd, opts)
        table.insert(state.calls, { cmd = cmd, opts = opts, win = vim.api.nvim_get_current_win() })
        vim.schedule(function()
            local ok, err = pcall(opts.on_exit, 1, code or 0, "exit")
            state.callback_error = not ok and tostring(err) or nil
            state.exited = true
        end)
        return 1
    end)
    return state
end

function M.wait_job(state)
    assert(vim.wait(1000, function()
        return state.exited
    end))
end

function M.run_job(action, code)
    local state = M.stub_jobstart(code)
    action()
    if #state.calls > 0 then
        M.wait_job(state)
    end
    return state
end

function M.ends_with(str, suffix)
    return str ~= nil and str:sub(-#suffix) == suffix
end

return M
