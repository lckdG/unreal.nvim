local log = require("unreal.log")
local pathUtils = require("unreal.path_utils")
local system = require("unreal.system")

local logLevel = vim.log.levels

local M = {}

---Open the matching source/header file. Searches under the Public/Private
---source root first, falls back to clangd's switch-source-header if unresolved.
function M.SwitchSourceHeader()
    local switchingFile = pathUtils.GetSourceHeader()
    if switchingFile ~= nil then
        vim.cmd.edit(vim.fn.fnameescape(switchingFile))
    elseif system.HasClangdEnabled() then
        vim.cmd("LspClangdSwitchSourceHeader")
    else
        log.Notify("No matching file name or clangd enabled!", logLevel.ERROR)
    end
end

---Compare a buffer content with the marker
--- TODO: use treesitter token for comparison
---@param buf number
---@param marker string
---@return number
function M.FindImplementation(buf, marker)
    -- String matching, should be token checks
    local bufLines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for index, line in ipairs(bufLines) do
        if line == marker then
            return index
        end
    end

    return -1
end

local function getInputSourceTypes(callback)
    local ui = require("unreal.ui")

    local items = ui.WrapList({ "All", "Headers", "Cpp" }, true)

    local prompt = "Select source types:"
    require("unreal.ui").Select(items, { prompt = prompt }, function (item)
        if item == nil then
            callback(nil)
            return
        end

        local index = item.value
        if index <= 0 or index > 3 then
            log.Notify("Invalid search choice " .. index, vim.log.levels.WARN)
            callback(nil)
        end

        if index == 1 then
            callback("*.{h,cpp}")
        elseif index == 2 then
            callback("*.h")
        elseif index == 3 then
            callback("*.cpp")
        else
            callback(nil)
        end
    end)
end

---Find header/cpp/both files via telescope. Prompts for scope:
---  1. All     - `*.{h,cpp}`
---  2. Headers - `*.h`
---  3. Cpp     - `*.cpp`
---The chosen glob is sent to telescope's ripgrep-backed `find_files` to filter results.
---No-ops if the prompt is dismissed or an invalid choice is entered.
function M.FindSource()
    getInputSourceTypes(function(globPattern)
        if globPattern == nil then
            return
        end

        local args = { "rg", "--files", "-g", globPattern }
        require("unreal.ui").FileSearch(args, { prompt = "Find source file: " })
        -- require("telescope.builtin").find_files({
        --     find_command = types,
        -- })
    end)
end

---Live grep header/cpp/both files via telescope. Prompts for scope:
---  1. All     - `*.{h,cpp}`
---  2. Headers - `*.h`
---  3. Cpp     - `*.cpp`
---The chosen glob is sent to telescope's ripgrep-backed `live_grep` to filter results.
---No-ops if the prompt is dismissed or an invalid choice is entered.
function M.GrepSource()
    getInputSourceTypes(function(globPattern)
        if globPattern == nil then
            return
        end

        local args = { "rg", "--vimgrep", "-S", "-g", globPattern }
        require("unreal.ui").GrepSearch(args, { prompt = "Grep source file: " })
        -- require("telescope.builtin").live_grep({
        --     additional_args = { "-g", globPattern },
        -- })
    end)
end

return M
