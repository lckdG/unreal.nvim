; Function declaration
(function_declarator (noexcept) @function.noexcept)

(field_declaration default_value: (_)) @function.skip
(function_definition) @function.skip

(template_declaration parameters: (template_parameter_list) @function.template)

(function_declarator
  declarator: (_) @function.name
  parameters: (parameter_list) @function.params
  (type_qualifier)? @function.const
  )

(unreal_function_declaration
  (ufunction_macro
    (unreal_argument_list
      (unreal_specifier_list
        (unreal_specifier) @function.specifier
        )
      )
    )
  )
