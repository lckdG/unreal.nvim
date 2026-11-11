local locate = require("unreal.locate")

local M = {}

---`:Unreal Code SwitchSourceHeader`: jump between `Foo.h` and `Foo.cpp`.
---Looks in the module's `Public/`/`Private/` folders first; if that finds nothing,
---asks clangd, which also knows files outside the usual layout.
function M.SwitchSourceHeader()
    local switchingFile = locate.GetSourceHeader()
    if switchingFile ~= nil then
        vim.cmd.edit(vim.fn.fnameescape(switchingFile))
    else
        require("unreal.lsp").SwitchSourceHeader()
    end
end

---Find the first line in `buf` exactly equal to `marker`.
--- TODO: use treesitter token for comparison
---@param buf number
---@param marker string
---@return number line 1-based line number, or -1 if not found
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
    local choices = {
        {
            name = "All",
            value = { "-g", "*.{h,cpp}" },
        },
        {
            name = "Headers",
            value = { "-g", "*.h" },
        },
        {
            name = "Cpp",
            value = { "-g", "*.cpp" },
        },
        {
            name = "Ini",
            value = {
                "--no-ignore",
                "-g",
                "!Intermediate/",
                "-g",
                "!Binaries/",
                "-g",
                "!CrashReportClient/",
                "-g",
                "*.ini",
            },
        },
        {
            name = "Build Files",
            value = { "-g", "*.{Build,Target}.cs" },
        },
    }

    local prompt = "Select source types:"
    require("unreal.ui").Select(choices, { prompt = prompt }, function(item)
        if item == nil then
            callback(nil)
            return
        end

        callback(item.value)
    end)
end

---`:Unreal Search Files`: find files by name with ripgrep (`rg`).
---First asks which kind of files to look at:
---  - All:         headers and sources (`.h`, `.cpp`)
---  - Headers:     `.h` only
---  - Cpp:         `.cpp` only
---  - Ini:         config files (`.ini`), also ignored ones such as `Saved/Config/`;
---                 generated copies in `Intermediate/`, `Binaries/`, `CrashReportClient/` are skipped
---  - Build Files: module and target rules (`.Build.cs`, `.Target.cs`)
---Then the active UI shows results: the quickfix list by default, a live picker with an
---extension such as Telescope. Cancelling the question does nothing.
function M.FindSource()
    getInputSourceTypes(function(globPattern)
        if globPattern == nil then
            return
        end

        local args = vim.list_extend({ "rg", "--files" }, globPattern)
        require("unreal.ui").FileSearch(args, { prompt = "Find source file: " })
    end)
end

---`:Unreal Search Grep`: search file contents with ripgrep (`rg`).
---Asks for the same kinds of files as `FindSource` (All, Headers, Cpp, Ini, Build Files),
---then the active UI asks for the text to search and shows matches: the quickfix list by default,
---a live picker with an extension such as Telescope. Cancelling the question does nothing.
function M.GrepSource()
    getInputSourceTypes(function(globPattern)
        if globPattern == nil then
            return
        end

        local args = vim.list_extend({ "rg", "--vimgrep", "-S" }, globPattern)
        require("unreal.ui").GrepSearch(args, { prompt = "Grep source file: " })
    end)
end

return M
