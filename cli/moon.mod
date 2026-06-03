name = "justjavac/lepus_cli"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "moonbitlang/parser@0.3.2",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/lepus/tree/main/cli"

license = "MIT"

keywords = [ "webview", "cli", "codegen" ]

description = "Developer CLI for Lepus."

options(
  source: "",
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
