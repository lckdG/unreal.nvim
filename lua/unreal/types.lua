local Types = {}

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
---@field telescope_extended_ignores table?
---@field clangd_build_args table?

---@class (exact) ExistedMacroVaiables
---@field arguments string[]
---@field metas string[]

---@class (exact) MacroCompletionRequest
---@field identifier string
---@field lspClient vim.lsp.Client
---@field exclusions string[]

---@class DeclarationTemplate
---@field [string] string?
---@field Skip boolean
---@field paramIdentifiers string[]
---@field ufunctionSpecifiers string[]

---@enum MacroAddType
Types.MACRO_ADD_TYPE = {
  First = 1,
  Append = 2,
  Prepend = 3,
  AppendMeta = 4,
}

return Types
