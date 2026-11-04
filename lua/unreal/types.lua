--- Module options

---@class (exact) UprojectFindOpts
---@field nameOnly boolean
---@field upward boolean

---@class (exact) ParseEnginePathOpts
---@field path string
---@field silent boolean
---@field savePath boolean

---@class (exact) QueryInfo
---@field bufnr number
---@field cursorRow number
---@field lang string?
---@field root TSNode?

---@class (exact) CustomTreesitterOpts
---@field url string
---@field revision string

---@class (exact) ConfigOpts
---@field custom_treesitter CustomTreesitterOpts?
---@field command_lead string
---@field cmd_abbreviations table?
---@field clangd_build_args table?
---@field extensions table<string, table|boolean>

--- Treesitter types

---@class (exact) ExistedMacroVaiables
---@field arguments string[]
---@field metas string[]

---@class (exact) MacroCompletionRequest
---@field identifier string
---@field exclusions string[]

---@class DeclarationTemplate
---@field [string] string?
---@field Skip boolean
---@field paramIdentifiers string[]
---@field ufunctionSpecifiers string[]

--- Ui Classes
---@class unreal.UiEntry
---@field name string
---@field value any
---@field desc? string[]

---@class unreal.UiProvider
---@field Select? fun(items: unreal.UiEntry[], opts: {prompt?: string}, cb: fun(value?: unreal.UiEntry))
---@field Input? fun(opts: {prompt?: string, default?: string, completion?: string}, cb: fun(text?: string))
---@field FileSearch? fun(searchArgs: string[], opts: {prompt?: string})
---@field GrepSearch? fun(searchArgs: string[], opts: {prompt?: string})

---

local Types = {}

---@enum MacroAddType
Types.MACRO_ADD_TYPE = {
    First = 1,
    Append = 2,
    Prepend = 3,
    AppendMeta = 4,
}

return Types
