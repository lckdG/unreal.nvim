local Job = {}

function Job.GetEfm()
    local platform = require("unreal.system").GetPlatform()
    if platform == "Win64" then
        return "%f(%l\\,%c): %trror %m,%f(%l): %trror %m,%-G%.%#"
    else
        return "%f:%l:%c: %trror: %m,%-G%.%#"
    end
end

---@param command string|string[]
---@param callback fun(exit_code, error_lines)
function Job.Start(command, callback)
    vim.cmd("botright new")
    local termWin = vim.api.nvim_get_current_win()

    local errors, chunk = {}, ""
    local efm = Job.GetEfm()
    local function collect(lines)
        lines = vim.tbl_map(function(line)
            return line:gsub("\27%[[%d;?]*%a", ""):gsub("\r", "")
        end, lines)
        vim.list_extend(errors, vim.fn.getqflist({ lines = lines, efm = efm }).items)
    end

    vim.fn.jobstart(command, {
        term = true,
        on_stdout = function(_, data)
            data[1] = chunk .. data[1]
            chunk = table.remove(data)
            collect(data)
        end,
        on_exit = function(_, exit_code)
            if chunk ~= "" then
                collect({ chunk })
            end

            if vim.api.nvim_win_is_valid(termWin) then
                vim.api.nvim_set_current_win(termWin)

                if exit_code == 0 then
                    vim.cmd("startinsert")
                end
            end

            callback(exit_code, errors)
        end,
    })

    vim.cmd("normal! G")
end

return Job
