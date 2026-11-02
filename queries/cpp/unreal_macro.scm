; Finding Unreal macros, UCLASS, USTRUCT, UFUNCTION and UPROPERTY
[
 (uclass_macro)
 (ustruct_macro)
 (ufunction_macro)
 (uproperty_macro)
 ] @macro.declaration

; Capture the indentifier names
(_
  (unreal_argument_list
    (unreal_specifier_list
      (unreal_specifier
        [
         key: (unreal_specifier_keyword) @macro.argument.identifier
         key: (identifier) @macro.argument.identifier
         (unreal_specifier_content . (unreal_specifier_keyword) @macro.argument.identifier)
         (unreal_specifier_content . (identifier) @macro.argument.identifier)
         value: (unreal_specifier_content
                  (unreal_specifier_list
                    (unreal_specifier
                      [
                       key: (unreal_specifier_keyword) @macro.meta.identifier
                       key: (identifier) @macro.meta.identifier
                       (unreal_specifier_content (unreal_specifier_keyword) @macro.meta.identifier)
                       (unreal_specifier_content (identifier) @macro.meta.identifier)
                       ]
                      )
                    )
                  )
         ]
        )
      )
    )
  )
