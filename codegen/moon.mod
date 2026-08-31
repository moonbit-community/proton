name = "moonbit-community/proton_codegen"

version = "0.2.3"

import {
  "moonbitlang/async@0.21.2",
  "moonbitlang/lexer@0.3.15",
  "moonbitlang/parser@0.3.18",
  "moonbitlang/x@0.5.1",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/codegen"

license = "Apache-2.0"

keywords = [ "proton", "codegen", "command", "wasm" ]

description = "WASM code generator for typed Proton command registrars."

preferred_target = "wasm"

supported_targets = "native+wasm"

options(
  warn_list: "",
)
