name = "justjavac/proton_cli"

version = "0.1.10"

import {
  "moonbitlang/x@0.4.43",
  "moonbitlang/parser@0.3.2",
  "justjavac/case@0.2.0",
}

readme = "codegen/README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cli"

license = "MIT"

keywords = [ "proton", "cli", "codegen" ]

description = "Developer CLI and code generation tools for Proton."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
