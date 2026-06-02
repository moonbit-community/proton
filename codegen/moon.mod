name = "justjavac/lepus_codegen"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "moonbitlang/parser@0.3.2",
}

readme = "README.md"

repository = "https://github.com/justjavac/lepus/tree/main/codegen"

license = "MIT"

keywords = [ "webview", "codegen", "cli" ]

description = "Build-time code generation helpers for Lepus."

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
