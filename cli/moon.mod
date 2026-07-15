name = "justjavac/proton_cli"

version = "0.1.6"

import {
  "justjavac/proton_config@0.1.5",
  "moonbitlang/x@0.4.43",
  "moonbitlang/parser@0.3.2",
  "justjavac/case@0.2.0",
  "moonbitlang/moon_config@0.3.5",
  "moonbitlang/lexer@0.3.5",
  "moonbitlang/async@0.20.1",
  "justjavac/ci@0.1.1",
  "justjavac/template@0.1.1",
  "justjavac/ffi@0.2.1",
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
