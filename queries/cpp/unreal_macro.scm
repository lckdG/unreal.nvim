; Finding Unreal macros, UCLASS, USTRUCT, UFUNCTION and UPROPERTY
(_
  (unreal_specifier_list
    (unreal_specifier
      ((unreal_specifier_keyword)? @macro.argument.identifier)
      )
    ?)
  ) @macro.declaration
(#any-of? @macro.declaration "uclass_macro" "ustruct_macro" "ufunction_macro" "uproperty_macro")
