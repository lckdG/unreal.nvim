local log = require('unreal.log')
local pathUtils = require('unreal.path_utils')
local system    = require('unreal.system')

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

local function getInputSourceTypes()
    local index = require('unreal.ui').SelectOptions('Select source types:', { 'All', 'Headers', 'Cpp' })

    if index <= 0 or index > 3 then
        log.Notify("Invalid search choice " .. index, vim.log.levels.WARN)
        return nil
    end

    if index == 1 then
        return "*.{h,cpp}"
    elseif index == 2 then
        return "*.h"
    elseif index == 3 then
        return "*.cpp"
    end

    return nil
end

---Find header/cpp/both files via telescope. Prompts for scope:
---  1. All     - `*.{h,cpp}`
---  2. Headers - `*.h`
---  3. Cpp     - `*.cpp`
---The chosen glob is sent to telescope's ripgrep-backed `find_files` to filter results.
---No-ops if the prompt is dismissed or an invalid choice is entered.
function M.FindSource()
    local globPattern = getInputSourceTypes()
    if globPattern == nil then return end

    local types = { "rg", "--files", "-g" , globPattern }
    require('telescope.builtin').find_files({
        find_command = types
    })
end

---Live grep header/cpp/both files via telescope. Prompts for scope:
---  1. All     - `*.{h,cpp}`
---  2. Headers - `*.h`
---  3. Cpp     - `*.cpp`
---The chosen glob is sent to telescope's ripgrep-backed `live_grep` to filter results.
---No-ops if the prompt is dismissed or an invalid choice is entered.
function M.GrepSource()
    local globPattern = getInputSourceTypes()
    if globPattern == nil then return end

    require('telescope.builtin').live_grep({
        additional_args = { '-g', globPattern }
    })
end

return M
