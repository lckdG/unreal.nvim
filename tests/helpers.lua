local M = {}

M.repo_root = vim.fn.getcwd()

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
        if type(ret) == "function" then return ret(...) end
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

function M.notified(list, pattern, level)
    for _, n in ipairs(list) do
        if n.msg:find(pattern, 1, true) and (level == nil or n.level == level) then
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
    vim.cmd("silent! %bwipeout!")
    vim.cmd.cd(vim.fn.fnameescape(M.repo_root))
end

function M.unload()
    for name in pairs(package.loaded) do
        if name:match("^unreal") then package.loaded[name] = nil end
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

function M.ends_with(str, suffix)
    return str ~= nil and str:sub(-#suffix) == suffix
end

return M
