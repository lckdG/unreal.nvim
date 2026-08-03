local M = {}

M.TypeDeclaration = {
    "unreal_class_declaration",
    "unreal_interface_declaration",
    "unreal_struct_declaration",
}

M.TypeIdentifier = "type_identifier"

M.DeclTypeKey = "function.type"

M.DeclKeys = {
    M.DeclTypeKey,
    "function.name",
    "function.params",
    "function.const",
}

return M
