local config = require('unreal.config')
local info = config.info
local utils = require('unreal.utils')
local logs = require('unreal.logs')
local logLevel = vim.log.levels

local M = {}

---Switching between source and header files by a simple custom search, fallback to clangd if the search fails
function M.SwitchSourceHeader()
    local switchingFile = utils.GetSourceHeader()
    if switchingFile ~= nil then
        vim.cmd("e " .. switchingFile)
    elseif utils.HasClangdEnabled() then
        vim.cmd("LspClangdSwitchSourceHeader")
    else
        logs.Notify("No matching file name or clangd enabled!", logLevel.ERROR)
    end
end

---Select the uproject file in current directory and perform action 'fn' on it
---@param fn function
---@param findOpts UprojectFindOpts
function M.SelectUproject(fn, findOpts)
    local projectFiles = utils.FindUprojects(findOpts)

    if #projectFiles == 1 then
        fn(projectFiles[1])
    else
        local prompt = "Multiple uprojects found, choose one:\n"
        for index, file in ipairs(projectFiles) do
            prompt = prompt .. tostring(index) .. ": " .. file .. "\n"
        end

        vim.ui.input({ prompt = prompt }, function (input)
            if input == nil or input == "" then
                return
            end

            local chosen = tonumber(input)
            fn(projectFiles[chosen])
        end)
    end
end

---Quickly open the uproject file in working directory
function M.OpenUproject()
    M.SelectUproject(function (projectPath)
        local executeCmd = utils.GetExecuteCmd()
        os.execute(executeCmd .. '"' .. projectPath .. '"')
    end, { nameOnly = false })
end

function M.RebuildClangd()
    if config.EnginePathSet == false then
        vim.cmd("Unreal SetEnginePath")
    end

    if config.BuildTool == nil then
        logs.Notify("No valid engine path found, aborting ", logLevel.WARN)
        return
    end

    M.SelectUproject(function (uproject)
        local projectName = vim.fn.fnamemodify(uproject, ":t:r")
        local projectEditor = projectName .. "Editor"

        local buildTool = config.BuildTool
        local buildCommand = "!dotnet " .. buildTool
                            .. " -mode=GenerateClangDatabase"
                            .. " " .. config.GetClangdBuildArgs()
                            .. " -project=" .. uproject
                            .. " -game -engine " .. projectEditor
                            .. " " .. utils.GetPlatform() .. " Development"
        vim.cmd(buildCommand)

        local sourceCC = vim.fs.joinpath(config.EnginePath, info.CCFile)
        local destCC = vim.fs.joinpath(vim.fn.getcwd(), info.CCFile)

        local ok, err = vim.uv.fs_copyfile(sourceCC, destCC)
        if ok then
            logs.Notify("Rebuild database successfully!", logLevel.INFO)
        else
            logs.Notify("Failed to copy compile_commands file: " .. tostring(err), logLevel.ERROR)
        end
    end, { nameOnly = false })
end

function M.ImplementFunction()
    local res = M.PrepareForFunctionImpl()
    if not res.success then
        logs.Notify(res.err, logLevel.ERROR)
        return
    end

    local parser = require('unreal.ast_parser')
    if not parser.PrepareForQuery() then
        logs.Notify("Failed to prepare for treesitter query", logLevel.ERROR)
        return
    end

    local node = res.ts_node
    local cppFile = res.cppFile

    if node == nil or cppFile == nil then return end

    local className = parser.GetRootIdentifier(node)
    if className == "" then
        logs.Notify("Unable to find class name for implementation creation!", logLevel.ERROR)
        return
    end

    local declarationTemplate = parser.GetDeclarationTemplate(className)
    if next(declarationTemplate) == nil then
        logs.Notify("Unable to create declaration template!", logLevel.ERROR)
        return
    end

    local parsed = M.ParseImplementation(declarationTemplate)
    local buf = utils.OpenBuffer(cppFile)

    local implLine = M.FindImplementation(buf, parsed[2])
    if implLine == -1 then
        local insertLine = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, insertLine, insertLine, false, parsed)

        implLine = insertLine
    end

    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { implLine, 0 })
    vim.cmd([[normal! zz]])
end

function M.PrepareForFunctionImpl()
    if vim.fn.expand("%:t:e") ~= info.HeaderExt then
        return {
            success = false,
            err = "Not a header file!",
            ts_node = nil,
            cppFile = nil,
        }
    end

    local node = vim.treesitter.get_node()
    if node == nil then
        return {
            success = false,
            err =  "Cannot find corresponding treesitter node!",
            ts_node = nil,
            cppFile = nil,
        }
    end

    local cppFile = utils.GetSourceHeader()
    if cppFile == nil then
        return {
            success = false,
            err = "Cannot find corresponding cpp file!",
            ts_node = nil,
            cppFile = nil,
        }
    end

    return {
        success = true,
        err = nil,
        ts_node = node,
        cppFile = cppFile
    }
end

---
---@param declaration table
---@return table
function M.ParseImplementation(declaration)
    local ast_parser = require('unreal.ast_parser')

    local declTypeKey = ast_parser.GetDeclTypeKey()
    local declKeys = ast_parser.GetDeclKeys()

    local content = {}
    local declarationText = ""

    for _, keyName in ipairs(declKeys) do
        if declaration[keyName] ~= nil then
            local appending = declaration[keyName]
            local space = (#declarationText > 0 and keyName ~= "function.params") and " " or ""

            declarationText = declarationText .. space .. appending
        end
    end

    table.insert(content, "")
    table.insert(content, declarationText)

    if declaration[declTypeKey] == nil then
        local constructorParams = table.concat(declaration.paramIdentifiers, ", ")
        table.insert(content, "\t: Super(" .. constructorParams .. ")")
    end

    table.insert(content, "{")
    table.insert(content, "\t// TODO:")
    table.insert(content, "}")

    return content
end

function M.FindImplementation(buf, marker)
    -- String matching, should be token checks
    local bufLines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for index, line in ipairs(bufLines) do
        if line == marker then
            logs.Notify("Function already defined at line " .. tostring(index), logLevel.INFO)
            return index
        end
    end

    return -1
end

local function trim(str)
    local res, _ = string.gsub(str, "^%s(.-)%s*$", '%1')
    return res
end

local function CreateCompletionEntry(rawEntry, exclusions)
    local label = trim(rawEntry.label)
    if vim.tbl_contains(exclusions, label) then
        return nil
    end

    local desc = ""
    if rawEntry["documentation"] then
        if type(rawEntry.documentation) == "string" then
            desc = rawEntry.documentation
        else
            desc = rawEntry.documentation.value
        end
    end

    local descLines = vim.split(desc, "\n")

    return {
        name = label,
        desc = descLines
    }
end

local function GetMacroCompletions(macroIdentifier, lspClient, exclusions, callback)
    local tempBufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(tempBufnr, "resolver")

    local namespace = string.sub(macroIdentifier, 1, 2)
    local insertTerm = namespace .. "::"

    vim.api.nvim_buf_set_lines(tempBufnr, 0, 0, false, { insertTerm })
    vim.lsp.buf_attach_client(tempBufnr, lspClient.id)

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(tempBufnr),
        position = {
            line = 0,
            character = #insertTerm
        },
        context = {
            triggerKind = 1, -- Invoked trigger
        }
    }

    vim.lsp.buf_request(tempBufnr, "textDocument/completion", params, function (err, result)
        if err ~= nil then
            print(err)
            callback(nil)
        else
            table.insert(exclusions, namespace)

            local entries = {}
            for _, item in ipairs(result.items) do
                local entry = CreateCompletionEntry(item, exclusions)
                if entry ~= nil then
                    table.insert(entries, entry)
                end
            end

            callback(entries)
        end
    end)

    vim.api.nvim_buf_delete(tempBufnr, { force = true })
end

local function EntryPicker(completionList, callback)
    local pickers = require('telescope.pickers')
    local previewers = require('telescope.previewers')
    local finders = require('telescope.finders')
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local conf = require('telescope.config').values

    local opts = {}
    pickers.new(opts, {
        prompt_title = "Attribute Picker",
        finder = finders.new_table {
            results = completionList,
            entry_maker = function (entry)
                return {
                    value = entry.name,
                    ordinal = entry.name,
                    display = entry.name,
                    desc = entry.desc,
                }
            end
        },
        sorter = conf.generic_sorter(opts),

        previewer = previewers.new_buffer_previewer({
            title = "Description",
            define_preview = function (self, entry, status)
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entry.desc)
            end,
        }),

        attach_mappings = function (prompt_bufnr)
            actions.select_default:replace(function ()
                actions.close(prompt_bufnr)

                local selection = action_state.get_selected_entry()
                callback(selection.value)
            end)

            return true
        end
    }):find()
end

function M.CompleteMacro()
    local clients = vim.lsp.get_clients({ name = "clangd" })
    if clients == nil or #clients <= 0 then
        return
    end


    local parser = require('unreal.ast_parser')

    if not parser.PrepareForQuery() then
        logs.Notify("Failed to prepare for treesitter query", logLevel.ERROR)
        return
    end

    local errorMsg = "No valid macro under cursor detected"
    local macroNode, macroIdentifier, existedVariables = parser.GetMacro()

    if macroNode == nil then
        logs.Notify(errorMsg, logLevel.ERROR)
        return
    end

    ---@type vim.lsp.Client
    local lspClient = clients[1]
    GetMacroCompletions(macroIdentifier, lspClient, existedVariables, function (completionList)
        if completionList == nil then
            return
        end

        EntryPicker(completionList, function (entry)
            local _, _, endRow, endCol = macroNode:range()
            local insertRow = endRow
            local insertCol = endCol - 1

            local insertion = #existedVariables > 0 and ", " .. entry or entry
            vim.api.nvim_buf_set_text(0, insertRow, insertCol, insertRow, insertCol, { insertion })
            vim.api.nvim_win_set_cursor(0, { insertRow + 1, insertCol + #insertion })
        end)
    end)
end

function M.getInputSourceTypes()
    local index = vim.fn.inputlist({'Select source types:', '1. All', '2. Headers', '3. Cpp'})

    if index <= 0 or index > 3 then
        logs.Notify("Invalid search choice " .. index, vim.log.levels.WARN)
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

function M.FindSource()
    local globPattern = M.getInputSourceTypes()
    if globPattern == nil then return end

    local types = { "rg", "--files", "-g" , globPattern }
    require('telescope.builtin').find_files({
        find_command = types
    })
end

function M.GrepSource()
    local globPattern = M.getInputSourceTypes()
    if globPattern == nil then return end

    require('telescope.builtin').live_grep({
        additional_args = { '-g', globPattern }
    })
end

return M

