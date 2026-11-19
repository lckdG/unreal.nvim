local helpers = require("unreal.helpers")

local Asset = {}
Asset.xxdValid = false

function Asset.init()
    Asset.xxdValid = vim.fn.executable("xxd") == 1
end

local function isCurrentBufferUbinary()
    local ext = vim.fs.ext(vim.api.nvim_buf_get_name(0))
    return vim.list_contains({ "umap", "uasset" }, ext)
end

function Asset.Hex()
    if not isCurrentBufferUbinary() then
        helpers.log.Notify("Not a .uasset or .umap file!", vim.log.levels.ERROR)
        return
    end

    if not Asset.xxdValid then
        helpers.log.Notify("xxd is not installed on this machine", vim.log.levels.ERROR)
        return
    end

    if vim.bo.modified then
        helpers.log.Notify("Buffer is modifying, save or discard your changes before proceeding", vim.log.levels.WARN)
        return
    end

    if vim.b.unreal_hex then
        return
    end

    local ft = vim.bo.filetype

    vim.cmd("e ++bin")
    vim.cmd("%!xxd -g 1")

    -- drop undo history so `u` cannot bring raw bytes back into hex mode
    local ul = vim.bo.undolevels
    vim.bo.undolevels = -1
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    vim.bo.undolevels = ul

    vim.bo.ft = "xxd"
    vim.bo.modified = false
    vim.b.unreal_hex = true

    Asset.CreateBufAutocmds(ft)
end

function Asset.CreateBufAutocmds(lastFt)
    local bufnr = vim.api.nvim_get_current_buf()

    local augroup_name = "unreal_hex_edit_" .. bufnr
    local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })

    local function leaveHex()
        vim.api.nvim_del_augroup_by_name(augroup_name)
        vim.b[bufnr].unreal_hex = nil
    end

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        group = augroup,
        buf = bufnr,
        callback = function(ev)
            local hex = table.concat(vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false), "\n") .. "\n"
            local ok, res = pcall(function()
                return vim.system({ "xxd", "-r" }, { stdin = hex, text = false }):wait()
            end)
            if not ok or res.code ~= 0 then
                helpers.log.Notify("xxd -r failed, file not written", vim.log.levels.ERROR)
                return
            end

            local f = assert(io.open(ev.file, "wb"))
            f:write(res.stdout)
            f:close()

            vim.bo[ev.buf].modified = false
            leaveHex()
            vim.cmd("e")
            vim.bo[ev.buf].filetype = lastFt
        end,
    })

    vim.api.nvim_create_autocmd("BufReadPost", {
        group = augroup,
        buf = bufnr,
        callback = function(ev)
            leaveHex()
            vim.bo[ev.buf].filetype = lastFt
        end,
    })
end

return Asset
