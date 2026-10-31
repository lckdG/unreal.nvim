
local M = {}

---@param opts ConfigOpts
function M.init(opts)
    local custom_treesitter_opts = opts.custom_treesitter
    M.Hijack(custom_treesitter_opts)
end

---@param custom_treesitter_opts CustomTreesitterOpts?
function M.Hijack(custom_treesitter_opts)
    if custom_treesitter_opts == nil then return end

    vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = function ()
            require('nvim-treesitter.parsers').cpp = {
                install_info = {
                    url = custom_treesitter_opts.url,
                    revision = custom_treesitter_opts.revision,
                },
                tier = 2
            }
        end
    })
end

return M
