name = "moonbit-community/proton_cli"

version = "0.1.16"

import {
  "moonbit-community/proton_config@0.1.16",
  "moonbit-community/proton_rsa@0.1.16",
  "moonbit-community/proton_updater@0.1.16",
  "moonbitlang/x@0.4.49",
  "moonbitlang/moon_config@0.3.5",
  "moonbitlang/async@0.20.5",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cli"

license = "Apache-2.0"

keywords = [ "proton", "cli", "desktop" ]

description = "Developer CLI for Proton desktop applications."

options(
  warn_list: "",
  preferred_target: "wasm",
  supported_targets: "native+wasm",
)
