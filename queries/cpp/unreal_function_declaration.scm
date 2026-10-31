; Function declaration
(_
  [
   (type_identifier)
   (primitive_type)
   ]? @function.type

  (function_declarator
    [
     (identifier)
     (field_identifier)
     ] @function.name
    (parameter_list
      (parameter_declaration
        (_
          ((identifier) @function.params.identifier)
          )
        )?
      ) @function.params
    (type_qualifier)? @function.const
    )
  )
