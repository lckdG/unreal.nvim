local h = dofile("tests/helpers.lua")
local lsp = require("unreal.lsp")

describe("lsp", function()
    local notes, edits

    before_each(function()
        notes = h.notifications()
        edits = h.spy(vim.cmd, "edit")
    end)
    after_each(h.reset)

    local function use_client(client)
        return h.spy(vim.lsp, "get_clients", client and { client } or {})
    end

    local function fake_client(opts)
        local client = { id = 1, name = "clangd", requests = {} }
        function client:supports_method(method)
            table.insert(self.requests, { supports = method })
            return opts.supported ~= false
        end
        function client:request(method, params, handler)
            table.insert(self.requests, { method = method, params = params })
            handler(opts.err, opts.result)
        end
        return client
    end

    describe("SwitchSourceHeader", function()
        it("no clangd client -> error notify, no edit", function()
            local calls = use_client(nil)
            lsp.SwitchSourceHeader()
            assert.are.same({ name = "clangd", bufnr = 0 }, calls[1][1])
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
            assert.are.equal(0, #edits)
        end)

        it("method not supported -> error notify, no request", function()
            local client = fake_client({ supported = false })
            use_client(client)
            lsp.SwitchSourceHeader()
            assert.is_true(h.notified(notes, vim.log.levels.ERROR, "textDocument/switchSourceHeader"))
            assert.are.same({ { supports = "textDocument/switchSourceHeader" } }, client.requests)
            assert.are.equal(0, #edits)
        end)

        it("uri returned -> request for current buffer, counterpart opened escaped", function()
            local target = vim.fs.joinpath(h.tmpdir(), "My Mod #1", "Foo%.cpp")
            local client = fake_client({ result = vim.uri_from_fname(target) })
            use_client(client)
            lsp.SwitchSourceHeader()
            assert.are.equal("textDocument/switchSourceHeader", client.requests[2].method)
            assert.are.same(vim.lsp.util.make_text_document_params(0), client.requests[2].params)
            assert.are.same({ { vim.fn.fnameescape(target) } }, edits)
        end)

        for _, case in ipairs({
            { "error", { err = { message = "boom" } } },
            { "nil uri", {} },
            { "empty uri", { result = "" } },
        }) do
            it(case[1] .. " -> warn notify, no edit", function()
                use_client(fake_client(case[2]))
                lsp.SwitchSourceHeader()
                assert.is_true(h.notified(notes, vim.log.levels.WARN))
                assert.are.equal(0, #edits)
            end)
        end
    end)

    describe("GetMacroCompletions", function()
        it("no clangd client -> error notify, empty list", function()
            use_client(nil)
            local attaches = h.spy(vim.lsp, "buf_attach_client")
            assert.are.same({}, lsp.GetMacroCompletions({ identifier = "UPROPERTY", exclusions = {} }))
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
            assert.are.equal(0, #attaches)
        end)
    end)
end)
