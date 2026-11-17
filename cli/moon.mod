name = "moonbit-community/proton_cli"

version = "0.9.0"

import {
  "moonbitlang/async@0.22.7",
  "moonbit-community/proton_config@0.9.0",
  "moonbit-community/proton_package@0.9.0",
  "moonbit-community/proton_cefsetup@0.9.0",
  "moonbit-community/proton_updater@0.9.0",
  "moonbitlang/x@0.5.5",
  "moonbitlang/moon_config@0.4.3",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/cli"

license = "Apache-2.0"

keywords = [ "proton", "cli", "desktop" ]

description = "Developer CLI for Proton desktop applications."

preferred_target = "wasm"

supported_targets = "native+wasm"

options(
  warn_list: "",
)
