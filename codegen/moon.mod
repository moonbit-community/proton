name = "moonbit-community/proton_codegen"

version = "0.1.19"

import {
  "moonbitlang/async@0.20.5",
  "moonbitlang/lexer@0.3.14",
  "moonbitlang/parser@0.3.14",
  "moonbitlang/x@0.4.50",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/codegen"

license = "Apache-2.0"

keywords = [ "proton", "codegen", "command", "wasm" ]

description = "WASM code generator for typed Proton command registrars."

options(
  warn_list: "",
  preferred_target: "wasm",
  supported_targets: "native+wasm",
)
