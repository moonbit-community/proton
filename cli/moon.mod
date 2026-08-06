name = "moonbit-community/proton_cli"

version = "0.1.14"

import {
  "moonbit-community/proton_config@0.1.14",
  "moonbit-community/proton_rsa@0.1.14",
  "moonbit-community/proton_updater@0.1.14",
  "moonbitlang/x@0.4.48",
  "moonbitlang/parser@0.3.12",
  "moonbitlang/moon_config@0.3.11",
  "moonbitlang/lexer@0.3.12",
  "moonbitlang/async@0.20.3",
  "moonbit-community/ffi@0.1.14",
}

readme = "codegen/README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cli"

license = "Apache-2.0"

keywords = [ "proton", "cli", "codegen" ]

description = "Developer CLI and code generation tools for Proton."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
