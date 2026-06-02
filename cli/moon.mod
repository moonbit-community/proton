name = "justjavac/lepus_cli"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "justjavac/lepus_codegen@0.1.0",
}

readme = "README.md"

repository = "https://github.com/justjavac/lepus/tree/main/cli"

license = "MIT"

keywords = [ "webview", "cli", "codegen" ]

description = "Developer CLI for Lepus."

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
