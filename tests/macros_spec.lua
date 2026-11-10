local h = dofile("tests/helpers.lua")
local macros = require("unreal.macros")
local treesitter = require("unreal.treesitter")

local HEADER = "Source/Mod/Public/Foo.h"

local function header(macroLine, decl)
    return {
        "#pragma once",
        "",
        "UCLASS(Blueprintable)",
        "class AFoo : public AActor",
        "{",
        "\tGENERATED_BODY()",
        "public:",
        "\t" .. macroLine,
        "\t" .. (decl or "int32 X;"),
        "};",
    }
end

local MACRO_ROW = 8

local function open(macroLine, decl)
    h.project({ [HEADER] = header(macroLine, decl) })
    h.edit(HEADER, MACRO_ROW)
end

describe("treesitter.GetMacro", function()
    after_each(h.reset)

    local cases = {
        {
            'UFUNCTION(BlueprintCallable, Category="X")',
            "void Foo();",
            "UFUNCTION",
            { "BlueprintCallable", "Category" },
            {},
        },
        { "UPROPERTY()", nil, "UPROPERTY", {}, {} },
        { "USTRUCT(BlueprintType)", "struct FBar {};", "USTRUCT", { "BlueprintType" }, {} },
        {
            'UPROPERTY(EditAnywhere, meta=(ClampMin="0", DisplayName="X"))',
            nil,
            "UPROPERTY",
            { "EditAnywhere" },
            { "ClampMin", "DisplayName" },
        },
        { 'UPROPERTY(meta=(ClampMin="0"))', nil, "UPROPERTY", {}, { "ClampMin" } },
    }
    for _, case in ipairs(cases) do
        it(case[1], function()
            open(case[1], case[2])
            local node, id, existing = treesitter.GetMacro()
            assert.is_not_nil(node)
            assert.are.equal(case[3], id)
            assert.are.same({ arguments = case[4], metas = case[5] }, existing)
        end)
    end

    it("UCLASS(Blueprintable)", function()
        open("UPROPERTY()")
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        local node, id, existing = treesitter.GetMacro()
        assert.is_not_nil(node)
        assert.are.equal("UCLASS", id)
        assert.are.same({ arguments = { "Blueprintable" }, metas = {} }, existing)
    end)

    it("plain C++ line -> nil node", function()
        open("UPROPERTY()")
        vim.api.nvim_win_set_cursor(0, { MACRO_ROW + 1, 1 })
        assert.is_nil((treesitter.GetMacro()))
    end)

    it("buffer without a treesitter language -> nil, '', empty lists", function()
        vim.cmd.enew()
        local node, id, existing = treesitter.GetMacro()
        assert.is_nil(node)
        assert.are.equal("", id)
        assert.are.same({ arguments = {}, metas = {} }, existing)
    end)
end)

describe("macros.CompleteMacro", function()
    local notes, requests, pickers

    before_each(function()
        notes = h.notifications()
        requests, pickers = {}, {}
        h.stub(vim.lsp, "get_clients", function()
            return { { id = 1, name = "clangd" } }
        end)
        h.stub(vim.lsp, "buf_attach_client", function()
            return true
        end)
        h.stub(vim.lsp, "buf_request", function(bufnr, method, params, handler)
            table.insert(requests, {
                bufnr = bufnr,
                method = method,
                params = params,
                handler = handler,
                lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false),
            })
        end)
        h.stub(require("unreal.ui"), "Select", function(list, opts, cb)
            table.insert(pickers, { list = list, opts = opts, cb = cb })
        end)
    end)
    after_each(h.reset)

    local function respond(i, result, err)
        local req = requests[i]
        assert.is_not_nil(req)
        return pcall(req.handler, err, result, { method = req.method, client_id = 1, bufnr = req.bufnr })
    end

    local function items(labels)
        local list = {}
        for _, l in ipairs(labels) do
            table.insert(list, { label = l })
        end
        return list
    end

    local function completions(...)
        return { items = items({ ... }) }
    end

    local function names(list)
        return vim.tbl_map(function(e)
            return e.name
        end, list)
    end

    local function complete(macroLine, nsResult, metaResult, decl)
        open(macroLine, decl)
        macros.CompleteMacro()
        assert.is_true((respond(1, nsResult)))
        assert.is_true((respond(2, metaResult)))
        return pickers[1]
    end

    it("no clangd -> error notify", function()
        h.stub(vim.lsp, "get_clients", function()
            return {}
        end)
        open("UPROPERTY()")
        macros.CompleteMacro()
        assert.is_true(h.notified(notes, vim.log.levels.ERROR))
        assert.are.equal(0, #requests)
    end)

    it("no macro under cursor -> error notify", function()
        open("UPROPERTY()")
        vim.api.nvim_win_set_cursor(0, { MACRO_ROW + 1, 1 })
        macros.CompleteMacro()
        assert.is_true(h.notified(notes, vim.log.levels.ERROR))
        assert.are.equal(0, #requests)
    end)

    for _, case in ipairs({
        { "UFUNCTION()", "void Foo();", "UF::" },
        { "UPROPERTY()", nil, "UP::" },
    }) do
        it(case[1] .. " requests " .. case[3] .. " first, then UM::", function()
            open(case[1], case[2])
            macros.CompleteMacro()
            assert.are.equal(1, #requests)
            assert.are.equal("textDocument/completion", requests[1].method)
            assert.are.same({ case[3] }, requests[1].lines)
            assert.are.same({ line = 0, character = #case[3] }, requests[1].params.position)

            respond(1, { items = {} })
            assert.are.equal(2, #requests)
            assert.are.same({ "UM::" }, requests[2].lines)
            assert.are.same({ line = 0, character = 4 }, requests[2].params.position)
        end)
    end

    it("each temp buffer stays valid until its response, then is deleted", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        local first = requests[1].bufnr
        assert.is_true(vim.api.nvim_buf_is_valid(first))
        respond(1, { items = {} })
        assert.is_false(vim.api.nvim_buf_is_valid(first))

        local second = requests[2].bufnr
        assert.is_true(vim.api.nvim_buf_is_valid(second))
        respond(2, { items = {} })
        assert.is_false(vim.api.nvim_buf_is_valid(second))
    end)

    it("nil responses -> no crash, picker not opened", function()
        assert.is_nil(complete("UPROPERTY()", nil, nil))
    end)

    for _, case in ipairs({
        {
            "CompletionList and CompletionItem[] responses -> merged, namespace first",
            "UPROPERTY()",
            { isIncomplete = false, items = items({ "EditAnywhere", "VisibleAnywhere" }) },
            items({ "ClampMin" }),
            { "UP::EditAnywhere", "UP::VisibleAnywhere", "UM::ClampMin" },
        },
        {
            "only meta results -> picker still opened",
            "UPROPERTY()",
            nil,
            completions("ClampMin"),
            { "UM::ClampMin" },
        },
        {
            "labels are trimmed on both sides",
            "UPROPERTY()",
            completions(" Foo", "Bar ", "  Baz  ", "\tQux"),
            nil,
            { "UP::Foo", "UP::Bar", "UP::Baz", "UP::Qux" },
        },
        {
            "namespace labels and existing specifiers/metas are excluded",
            'UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))',
            completions("UP", "VisibleAnywhere", "EditAnywhere"),
            completions("UM", "ClampMin", "ClampMax"),
            { "UP::EditAnywhere", "UM::ClampMax" },
        },
        {
            "existing specifier does not exclude a meta of the same name",
            "UPROPERTY(DisplayName)",
            completions("DisplayName"),
            completions("DisplayName"),
            { "UM::DisplayName" },
        },
    }) do
        it(case[1] .. ", text and isMeta follow the name", function()
            local list = complete(case[2], case[3], case[4]).list
            assert.are.same(case[5], names(list))
            for _, entry in ipairs(list) do
                assert.are.equal(entry.name:match("::(.*)$"), entry.value.text)
                assert.are.equal(vim.startswith(entry.name, "UM::"), entry.value.isMeta)
            end
        end)
    end

    it("LSP error -> error notify, picker not opened", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        assert.is_true((respond(1, nil, { code = -32603, message = "boom" })))
        respond(2, nil)
        assert.are.equal(0, #pickers)
        assert.is_true(h.notified(notes, vim.log.levels.ERROR, "boom"))
    end)

    it("exclusions do not mutate existedVariables from GetMacro", function()
        local existing
        local getMacro = treesitter.GetMacro
        h.stub(treesitter, "GetMacro", function()
            local node, id, ev = getMacro()
            existing = ev
            return node, id, ev
        end)
        complete(
            'UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))',
            completions("EditAnywhere"),
            completions("ClampMax")
        )
        assert.are.same({ arguments = { "VisibleAnywhere" }, metas = { "ClampMin" } }, existing)
    end)

    it("comma insertion comes from the syntax tree, not from existedVariables", function()
        local getMacro = treesitter.GetMacro
        h.stub(treesitter, "GetMacro", function()
            local node, id = getMacro()
            return node, id, { arguments = {}, metas = {} }
        end)
        complete("UPROPERTY(VisibleAnywhere)", completions("EditAnywhere"), nil).cb({
            text = "EditAnywhere",
            isMeta = false,
        })
        assert.are.equal("\tUPROPERTY(VisibleAnywhere, EditAnywhere)", vim.api.nvim_get_current_line())
    end)

    it("documentation: string, MarkupContent, none", function()
        local list = complete("UPROPERTY()", {
            items = {
                { label = "A", documentation = "line1\nline2" },
                { label = "B", documentation = { kind = "markdown", value = "md" } },
                { label = "C" },
            },
        }, nil).list
        assert.are.same({ { "line1", "line2" }, { "md" }, { "" } }, {
            list[1].desc,
            list[2].desc,
            list[3].desc,
        })
    end)

    it("picker cancelled (nil entry) -> buffer unchanged", function()
        complete("UPROPERTY()", completions("EditAnywhere"), nil).cb(nil)
        assert.are.equal("\tUPROPERTY()", vim.api.nvim_get_current_line())
    end)

    it("two calls before any response -> distinct temp buffers, no error", function()
        open("UPROPERTY()")
        assert.is_true((pcall(macros.CompleteMacro)))
        assert.is_true((pcall(macros.CompleteMacro)))
        assert.are.equal(2, #requests)
        assert.are_not.equal(requests[1].bufnr, requests[2].bufnr)
        assert.are_not.equal(vim.api.nvim_buf_get_name(requests[1].bufnr), vim.api.nvim_buf_get_name(requests[2].bufnr))
    end)

    it("macro spanning several lines, cursor on first line -> inserted before ')'", function()
        complete("UPROPERTY(VisibleAnywhere,", completions("EditAnywhere"), nil, '\tCategory="X")').cb({
            text = "EditAnywhere",
            isMeta = false,
        })
        assert.are.same(
            { "\tUPROPERTY(VisibleAnywhere,", '\t\tCategory="X", EditAnywhere)' },
            vim.api.nvim_buf_get_lines(0, MACRO_ROW - 1, MACRO_ROW + 1, false)
        )
    end)

    local spec = function(text)
        return { text = text, isMeta = false }
    end
    local meta = function(text)
        return { text = text, isMeta = true }
    end
    for _, case in ipairs({
        { "UPROPERTY()", spec("EditAnywhere"), "\tUPROPERTY(EditAnywhere)" },
        { "UPROPERTY()", meta("ClampMin"), "\tUPROPERTY(meta = (ClampMin))" },
        { "UPROPERTY(VisibleAnywhere)", spec("EditAnywhere"), "\tUPROPERTY(VisibleAnywhere, EditAnywhere)" },
        { "UPROPERTY(VisibleAnywhere)", meta("ClampMin"), "\tUPROPERTY(VisibleAnywhere, meta = (ClampMin))" },
        {
            'UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))',
            spec("EditAnywhere"),
            '\tUPROPERTY(VisibleAnywhere, EditAnywhere, meta=(ClampMin="0"))',
        },
        {
            'UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))',
            meta("ClampMax"),
            '\tUPROPERTY(VisibleAnywhere, meta=(ClampMin="0", ClampMax))',
        },
        { 'UPROPERTY(meta=(ClampMin="0"))', spec("EditAnywhere"), '\tUPROPERTY(EditAnywhere, meta=(ClampMin="0"))' },
    }) do
        it(("insert %s%s into %s"):format(case[2].isMeta and "meta " or "", case[2].text, case[1]), function()
            complete(case[1], completions("EditAnywhere"), nil).cb(case[2])
            assert.are.equal(case[3], vim.api.nvim_get_current_line())
            local cursor = vim.api.nvim_win_get_cursor(0)
            assert.are.equal(MACRO_ROW, cursor[1])
            assert.is_truthy(case[3]:sub(1, cursor[2]):match(vim.pesc(case[2].text) .. "[,)]?%s?$"))
        end)
    end
end)
