local h = dofile("tests/helpers.lua")
local asset = require("unreal.asset")

describe("asset", function()
    local BYTES = "\xC1\x83\x2A\x9E\x00\x0A\xFF\x0D\x0A"
    local path, notes

    local function read(file)
        local f = assert(io.open(file, "rb"))
        local data = f:read("a")
        f:close()
        return data
    end

    local function fixture(name)
        local file = vim.fs.joinpath(h.tmpdir(), name)
        local f = assert(io.open(file, "wb"))
        f:write(BYTES)
        f:close()
        return file
    end

    local function writeHandlers()
        return #vim.api.nvim_get_autocmds({ event = "BufWriteCmd", buffer = 0 })
    end

    before_each(function()
        asset.init()
        notes = h.notifications()
        path = fixture("Test.uasset")
        vim.cmd.edit(vim.fn.fnameescape(path))
    end)
    after_each(h.reset)

    it("Hex -> xxd dump, unmodified, write handler set", function()
        asset.Hex()
        assert.are.equal("xxd", vim.bo.filetype)
        assert.is_true(vim.startswith(vim.fn.getline(1), "00000000: c1 83 2a 9e 00 0a ff 0d 0a"))
        assert.is_false(vim.bo.modified)
        assert.is_true(vim.b.unreal_hex)
        assert.are.equal(1, writeHandlers())
    end)

    it("Hex, :w -> bytes identical, buffer back to raw", function()
        local ft = vim.bo.filetype
        asset.Hex()
        vim.cmd("silent w")
        assert.are.equal(BYTES, read(path))
        assert.is_nil(vim.b.unreal_hex)
        assert.are.equal(0, writeHandlers())
        assert.are.equal(ft, vim.bo.filetype)
        assert.is_true(vim.startswith(vim.fn.getline(1), "\xC1\x83\x2A\x9E"))
    end)

    it("edit a byte, :w -> only that byte changes", function()
        asset.Hex()
        vim.cmd("s/c1/aa/")
        vim.cmd("silent w")
        assert.are.equal("\xAA" .. BYTES:sub(2), read(path))
    end)

    it("works on .umap", function()
        path = fixture("Test.umap")
        vim.cmd.edit(vim.fn.fnameescape(path))
        asset.Hex()
        vim.cmd("silent w")
        assert.are.equal(BYTES, read(path))
    end)

    it("undo after Hex -> nothing to undo, :w keeps bytes", function()
        asset.Hex()
        vim.cmd("silent! undo")
        assert.is_true(vim.startswith(vim.fn.getline(1), "00000000:"))
        vim.cmd("silent w")
        assert.are.equal(BYTES, read(path))
    end)

    it("Hex twice -> second call is a no-op", function()
        asset.Hex()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        asset.Hex()
        assert.are.same(lines, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.are.equal(1, writeHandlers())
    end)

    it("xxd -r fails -> file untouched, error, still in hex mode", function()
        asset.Hex()
        h.stub(vim, "system", function()
            return {
                wait = function()
                    return { code = 1, stdout = "", stderr = "boom" }
                end,
            }
        end)
        vim.cmd("silent w")
        assert.are.equal(BYTES, read(path))
        assert.is_true(h.notified(notes, vim.log.levels.ERROR, "xxd -r failed"))
        assert.is_true(vim.b.unreal_hex)
        assert.are.equal(1, writeHandlers())
    end)

    it(":e in hex mode -> handler removed, :w writes raw bytes", function()
        asset.Hex()
        vim.cmd("silent e")
        assert.is_nil(vim.b.unreal_hex)
        assert.are.equal(0, writeHandlers())
        vim.cmd("silent w")
        assert.are.equal(BYTES, read(path))
    end)

    it("modified buffer -> warns, stays raw", function()
        vim.api.nvim_buf_set_lines(0, -1, -1, false, { "x" })
        asset.Hex()
        assert.is_true(h.notified(notes, vim.log.levels.WARN, "save or discard"))
        assert.is_nil(vim.b.unreal_hex)
        assert.are.equal(0, writeHandlers())
    end)

    it("not a .uasset / .umap -> error", function()
        vim.cmd.edit(vim.fn.fnameescape(h.write(h.tmpdir(), "a.txt", { "x" })))
        asset.Hex()
        assert.is_true(h.notified(notes, vim.log.levels.ERROR, "Not a .uasset or .umap"))
        assert.is_nil(vim.b.unreal_hex)
    end)

    it("xxd missing -> error, stays raw", function()
        h.stub(asset, "xxdValid", false)
        asset.Hex()
        assert.is_true(h.notified(notes, vim.log.levels.ERROR, "xxd is not installed"))
        assert.is_nil(vim.b.unreal_hex)
        assert.are.equal(0, writeHandlers())
    end)
end)
