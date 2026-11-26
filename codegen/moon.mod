name = "moonbit-community/proton_codegen"

version = "0.10.1"

import {
  "moonbitlang/lexer@0.4.4",
  "moonbitlang/parser@0.4.4",
  "moonbitlang/x@0.5.7",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/codegen"

license = "Apache-2.0"

keywords = [ "proton", "codegen", "command", "wasm" ]

description = "WASM code generator for typed Proton command registrars."

preferred_target = "wasm"

supported_targets = "native+wasm"
