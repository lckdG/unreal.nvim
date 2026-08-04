local M = {}

local function get_version(name)
    local output = vim.fn.system(name .. " --version")
    if vim.v.shell_error ~= 0 then return nil end

    return vim.trim(output:match("[^\r\n]+") or output)
end

local function check_executable(name, hint)
    local health = vim.health
    if vim.fn.executable(name) == 1 then
        local version = get_version(name)
        if version then
            health.ok(name .. " found (" .. version .. ")")
        else
            health.ok(name .. " found")
        end
    else
        health.error(name .. " not found", hint)
    end
end

local function check_telescope()
    local health = vim.health
    local ok = pcall(require, "telescope")
    if ok then
        health.ok("telescope.nvim found")
    else
        health.error("telescope.nvim not found", "required for search commands")
    end
end

local function check_engine_path()
    local health = vim.health
    local enginePath = require("unreal.config").ReadEnginePath()

    if enginePath then
        health.ok("Engine path found: " .. enginePath)
    else
        health.warn("No engine path set for current project", "Run :Unreal SetEnginePath")
    end
end

function M.check()
    local health = vim.health

    health.start("unreal.nvim")

    check_telescope()
    check_executable("rg", "telescope.nvim dependency")
    check_executable("clangd", "for LSP functionalities")
    check_executable("dotnet", "for Unreal tools, e.g. UBT, UHT,...")
    check_engine_path()
end

return M

