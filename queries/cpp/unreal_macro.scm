; Finding Unreal macros, UCLASS, USTRUCT, UFUNCTION and UPROPERTY
(_
  (unreal_argument_list
    (unreal_specifier_list
      (unreal_specifier
          (_) @macro.argument.identifier
        )
      )
    ?)
  ) @macro.declaration
(#any-of? @macro.declaration "uclass_macro" "ustruct_macro" "ufunction_macro" "uproperty_macro")
(#any-of? @macro.argument.identifier "unreal_specifier_keyword" "identifier")
