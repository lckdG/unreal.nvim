if exists("b:current_syntax")
    finish
endif

syn match unrealLogTime /^\[[^]]*\]\[[^]]*\]/ nextgroup=unrealLogCategory
syn match unrealLogCategory /\w\+:/ contained nextgroup=unrealLogFatal,unrealLogError,unrealLogWarning,unrealLogDisplay,unrealLogVerbose skipwhite
syn match unrealLogLineStart /^\w\+:/ nextgroup=unrealLogFatal,unrealLogError,unrealLogWarning,unrealLogDisplay,unrealLogVerbose skipwhite

syn match unrealLogFatal /Fatal:.*/ contained
syn match unrealLogError /Error:.*/ contained
syn match unrealLogWarning /Warning:.*/ contained
syn match unrealLogDisplay /Display:/ contained
syn match unrealLogVerbose /\(Very\)\?Verbose:.*/ contained

syn match unrealLogSource /\f\+\.\(cpp\|h\)(\d\+)/

hi def link unrealLogTime Comment
hi def link unrealLogCategory Identifier
hi def link unrealLogLineStart Identifier
hi def link unrealLogFatal DiagnosticError
hi def link unrealLogError DiagnosticError
hi def link unrealLogWarning DiagnosticWarn
hi def link unrealLogDisplay DiagnosticInfo
hi def link unrealLogVerbose Comment
hi def link unrealLogSource Underlined

let b:current_syntax = "unreallog"
