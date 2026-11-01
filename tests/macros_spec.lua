local h = dofile("tests/helpers.lua")
local macros = require("unreal.macros")
local treesitter = require("unreal.treesitter")

local HEADER = "Source/Mod/Public/Foo.h"

local function header(macroLine, decl)
    return {
        "#pragma once", "",
        "UCLASS(Blueprintable)", "class AFoo : public AActor", "{", "\tGENERATED_BODY()", "public:",
        "\t" .. macroLine, "\t" .. (decl or "int32 X;"),
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
        { 'UFUNCTION(BlueprintCallable, Category="X")', "void Foo();", "UFUNCTION", { "BlueprintCallable", "Category" }, {} },
        { "UPROPERTY()", nil, "UPROPERTY", {}, {} },
        { "USTRUCT(BlueprintType)", "struct FBar {};", "USTRUCT", { "BlueprintType" }, {} },
        { 'UPROPERTY(EditAnywhere, meta=(ClampMin="0", DisplayName="X"))', nil, "UPROPERTY", { "EditAnywhere" }, { "ClampMin", "DisplayName" } },
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
        h.stub(vim.lsp, "get_clients", function() return { { id = 1, name = "clangd" } } end)
        h.stub(vim.lsp, "buf_attach_client", function() return true end)
        h.stub(vim.lsp, "buf_request", function(bufnr, method, params, handler)
            table.insert(requests, {
                bufnr = bufnr, method = method, params = params, handler = handler,
                lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false),
            })
        end)
        h.stub(require("unreal.ui"), "EntryPicker", function(list, cb)
            table.insert(pickers, { list = list, cb = cb })
        end)
    end)
    after_each(h.reset)

    -- requests are sequential: [1] = macro namespace (UP::/UF::/...), [2] = UM:: (sent after [1] resolves)
    local function respond(i, result, err)
        local req = requests[i]
        assert.is_not_nil(req, "request " .. i .. " was not sent")
        return pcall(req.handler, err, result, { method = req.method, client_id = 1, bufnr = req.bufnr })
    end

    local function respondBoth(nsResult, metaResult)
        local ok, e = respond(1, nsResult)
        assert.is_true(ok, tostring(e))
        ok, e = respond(2, metaResult)
        assert.is_true(ok, tostring(e))
    end

    local function items(labels)
        local list = {}
        for _, l in ipairs(labels) do table.insert(list, { label = l }) end
        return list
    end

    local function names(list) return vim.tbl_map(function(e) return e.name end, list) end
    local function texts(list) return vim.tbl_map(function(e) return e.value.text end, list) end

    it("no clangd -> error notify", function()
        h.stub(vim.lsp, "get_clients", function() return {} end)
        open("UPROPERTY()")
        macros.CompleteMacro()
        assert.is_true(h.notified(notes, "Clangd is not enabled for current buffer!", vim.log.levels.ERROR))
        assert.are.equal(0, #requests)
    end)

    it("no macro under cursor -> error notify", function()
        open("UPROPERTY()")
        vim.api.nvim_win_set_cursor(0, { MACRO_ROW + 1, 1 })
        macros.CompleteMacro()
        assert.is_true(h.notified(notes, "No valid macro under cursor detected", vim.log.levels.ERROR))
        assert.are.equal(0, #requests)
    end)

    local namespaces = {
        { "UFUNCTION()", "void Foo();", "UF::" },
        { "UPROPERTY()", nil, "UP::" },
    }
    for _, case in ipairs(namespaces) do
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
        open("UPROPERTY()")
        macros.CompleteMacro()
        respondBoth(nil, nil)
        assert.are.equal(0, #pickers)
    end)

    it("CompletionList and CompletionItem[] responses -> merged, namespace first", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        respondBoth({ isIncomplete = false, items = items({ "EditAnywhere", "VisibleAnywhere" }) }, items({ "ClampMin" }))
        assert.are.same({ "UP::EditAnywhere", "UP::VisibleAnywhere", "UM::ClampMin" }, names(pickers[1].list))
        assert.are.same({ "EditAnywhere", "VisibleAnywhere", "ClampMin" }, texts(pickers[1].list))
    end)

    it("only meta results -> picker still opened", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        respondBoth(nil, { items = items({ "ClampMin" }) })
        assert.are.same({ "UM::ClampMin" }, names(pickers[1].list))
    end)

    it("entries are flagged isMeta by namespace", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        respondBoth({ items = items({ "EditAnywhere" }) }, { items = items({ "ClampMin" }) })
        assert.is_false(pickers[1].list[1].value.isMeta)
        assert.is_true(pickers[1].list[2].value.isMeta)
    end)

    it("LSP error -> error notify, picker not opened", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        local ok, e = respond(1, nil, { code = -32603, message = "boom" })
        assert.is_true(ok, tostring(e))
        respond(2, nil)
        assert.are.equal(0, #pickers)
        assert.is_true(h.notified(notes, "boom", vim.log.levels.ERROR))
    end)

    it("labels are trimmed on both sides", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        respondBoth({ items = items({ " Foo", "Bar ", "  Baz  ", "\tQux" }) }, nil)
        assert.are.same({ "Foo", "Bar", "Baz", "Qux" }, texts(pickers[1].list))
    end)

    it("namespace labels and existing specifiers/metas are excluded", function()
        open('UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))')
        macros.CompleteMacro()
        respondBoth(
            { items = items({ "UP", "VisibleAnywhere", "EditAnywhere" }) },
            { items = items({ "UM", "ClampMin", "ClampMax" }) }
        )
        assert.are.same({ "UP::EditAnywhere", "UM::ClampMax" }, names(pickers[1].list))
    end)

    it("existing specifier does not exclude a meta of the same name", function()
        open("UPROPERTY(DisplayName)")
        macros.CompleteMacro()
        respondBoth({ items = items({ "DisplayName" }) }, { items = items({ "DisplayName" }) })
        assert.are.same({ "UM::DisplayName" }, names(pickers[1].list))
    end)

    -- regression: commas used to be derived from #existedVariables after the namespace was inserted into it
    it("exclusions do not mutate existedVariables from GetMacro", function()
        local existing
        local getMacro = treesitter.GetMacro
        h.stub(treesitter, "GetMacro", function()
            local node, id, ev = getMacro()
            existing = ev
            return node, id, ev
        end)
        open('UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))')
        macros.CompleteMacro()
        respondBoth({ items = items({ "EditAnywhere" }) }, { items = items({ "ClampMax" }) })
        assert.are.same({ arguments = { "VisibleAnywhere" }, metas = { "ClampMin" } }, existing)
    end)

    it("comma insertion comes from the syntax tree, not from existedVariables", function()
        local getMacro = treesitter.GetMacro
        h.stub(treesitter, "GetMacro", function()
            local node, id = getMacro()
            return node, id, { arguments = {}, metas = {} }
        end)
        open("UPROPERTY(VisibleAnywhere)")
        macros.CompleteMacro()
        respondBoth({ items = items({ "EditAnywhere" }) }, nil)
        pickers[1].cb({ text = "EditAnywhere", isMeta = false })
        assert.are.equal("\tUPROPERTY(VisibleAnywhere, EditAnywhere)", vim.api.nvim_get_current_line())
    end)

    it("documentation: string, MarkupContent, none", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        respondBoth({ items = {
            { label = "A", documentation = "line1\nline2" },
            { label = "B", documentation = { kind = "markdown", value = "md" } },
            { label = "C" },
        } }, nil)
        local list = pickers[1].list
        assert.are.same({ "line1", "line2" }, list[1].desc)
        assert.are.same({ "md" }, list[2].desc)
        assert.are.same({ "" }, list[3].desc)
    end)

    it("picker cancelled (nil entry) -> buffer unchanged", function()
        open("UPROPERTY()")
        macros.CompleteMacro()
        respondBoth({ items = items({ "EditAnywhere" }) }, nil)
        pickers[1].cb(nil)
        assert.are.equal("\tUPROPERTY()", vim.api.nvim_get_current_line())
    end)

    local spec = function(text) return { text = text, isMeta = false } end
    local meta = function(text) return { text = text, isMeta = true } end
    local inserts = {
        { "UPROPERTY()", spec("EditAnywhere"), "\tUPROPERTY(EditAnywhere)" },
        { "UPROPERTY()", meta("ClampMin"), "\tUPROPERTY(meta = (ClampMin))" },
        { "UPROPERTY(VisibleAnywhere)", spec("EditAnywhere"), "\tUPROPERTY(VisibleAnywhere, EditAnywhere)" },
        { "UPROPERTY(VisibleAnywhere)", meta("ClampMin"), "\tUPROPERTY(VisibleAnywhere, meta = (ClampMin))" },
        { 'UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))', spec("EditAnywhere"), '\tUPROPERTY(VisibleAnywhere, EditAnywhere, meta=(ClampMin="0"))' },
        { 'UPROPERTY(VisibleAnywhere, meta=(ClampMin="0"))', meta("ClampMax"), '\tUPROPERTY(VisibleAnywhere, meta=(ClampMin="0", ClampMax))' },
        { 'UPROPERTY(meta=(ClampMin="0"))', spec("EditAnywhere"), '\tUPROPERTY(EditAnywhere, meta=(ClampMin="0"))' },
    }
    for _, case in ipairs(inserts) do
        it(("insert %s%s into %s"):format(case[2].isMeta and "meta " or "", case[2].text, case[1]), function()
            open(case[1])
            macros.CompleteMacro()
            respondBoth({ items = items({ "EditAnywhere" }) }, nil)
            pickers[1].cb(case[2])
            assert.are.equal(case[3], vim.api.nvim_get_current_line())
            -- cursor lands right after the inserted content (text plus its closing paren / ", " separator, if any)
            local cursor = vim.api.nvim_win_get_cursor(0)
            assert.are.equal(MACRO_ROW, cursor[1])
            assert.is_truthy(case[3]:sub(1, cursor[2]):match(vim.pesc(case[2].text) .. "[,)]?%s?$"))
        end)
    end
end)
