name = "moonbit-community/proton_cli"

version = "0.1.15"

import {
  "moonbit-community/proton_config@0.1.15",
  "moonbit-community/proton_rsa@0.1.15",
  "moonbit-community/proton_updater@0.1.15",
  "moonbitlang/x@0.4.49",
  "moonbitlang/parser@0.3.13",
  "moonbitlang/moon_config@0.3.5",
  "moonbitlang/lexer@0.3.13",
  "moonbitlang/async@0.20.5",
}

readme = "codegen/README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cli"

license = "Apache-2.0"

keywords = [ "proton", "cli", "codegen" ]

description = "Developer CLI and code generation tools for Proton."

options(
  warn_list: "",
  preferred_target: "wasm",
  supported_targets: "native+wasm",
)
