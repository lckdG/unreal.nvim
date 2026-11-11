---@class unreal.helpers.Xml
local Xml = {}

local function decode(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

---@param xmlPath string
---@param tags string[]
---@return table
function Xml.GetTagContent(xmlPath, tags)
    local result = {}

    local file = io.open(xmlPath)
    if file then
        local content = file:read("*a")
        file:close()

        for _, tag in ipairs(tags) do
            local t = vim.pesc(tag)
            local matchPattern = "<" .. t .. ">(.-)</" .. t .. ">"

            local tagContent = content:match(matchPattern)
            if tagContent then
                result[tag] = {}

                for line in vim.gsplit(tagContent, "\n", { trimempty = true }) do
                    line = decode(vim.fn.trim(line))
                    table.insert(result[tag], line)
                end
            end
        end
    end

    return result
end

---@param xmlPath string
---@return table?
function Xml.ParseCallStack(xmlPath)
    local tag = "CallStack"
    local result = Xml.GetTagContent(xmlPath, { tag })
    local callstackContent = result[tag]

    local items = {}
    if callstackContent then
        for _, line in ipairs(callstackContent) do
            local func, filename, num = line:match("^(.*) %[(.+):(%d+)%]$")
            if func then
                table.insert(items, { filename = vim.fs.normalize(filename), lnum = tonumber(num), text = func })
            else
                table.insert(items, { text = line })
            end
        end

        return items
    end

    return nil
end

return Xml
